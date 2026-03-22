package ds.pipelines;

import haxe.Unit;
import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.UInt8Array;
import haxe.io.ArrayBufferView;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.Out;
import hxcoro.ds.pipelines.pipe.State;
import hxcoro.ds.pipelines.pipe.PipeReader;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;
import atest.Test;

private class TestContinuation implements IContinuation<Unit> {
	public var resumed : Bool;

	public var context (get, never) : Context;

	function get_context():Context {
		return Context.create(new TrampolineDispatcher());
	}

	public function new() {
		resumed = false;
	}

	public function resume(_:Null<Unit>, _:Null<Exception>) {
		resumed = true;
	}
}

class TestPipeReader extends Test {
	private static function arrayBufferViewFromBytes(bytes:Bytes):ArrayBufferView {
#if js
		return cast UInt8Array.fromBytes(bytes);
#else
		return ArrayBufferView.fromBytes(bytes);
#end
	}

	public function test_tryRead() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final data   = new ArrayBufferView(16);

		Assert.isTrue(state.channel.writer.tryWrite(data));

		final out = new Out();
		if (Assert.isTrue(reader.tryRead(out))) {
			Assert.equals(data.byteLength, out.get().byteLength);
		}
		
		final out = new Out();
		Assert.isFalse(state.channel.reader.tryRead(out));
	}

	public function test_tryRead_no_data() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);

		final out = new Out();
		Assert.isFalse(reader.tryRead(out));
	}

	public function test_tryRead_null_out() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);

		Assert.raises(() -> reader.tryRead(null), ArgumentException);
	}

	public function test_tryReadAtLeast() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final data   = new ArrayBufferView(16);

		Assert.isTrue(state.channel.writer.tryWrite(data));

		final out = new Out();
		if (Assert.isTrue(reader.tryReadAtLeast(8, out))) {
			Assert.equals(data.byteLength, out.get().byteLength);
		}
		
		final out = new Out();
		Assert.isFalse(state.channel.reader.tryRead(out));
	}

	public function test_tryReadAtLeast_not_enough_data() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);

		Assert.isTrue(state.channel.writer.tryWrite(arrayBufferViewFromBytes(Bytes.ofString("Hello"))));

		final out = new Out();
		Assert.isFalse(reader.tryReadAtLeast(10, out));

		Assert.isTrue(state.channel.writer.tryWrite(arrayBufferViewFromBytes(Bytes.ofString("World"))));

		final out = new Out();
		Assert.isTrue(reader.tryReadAtLeast(10, out));
	}

	public function test_tryReadAtLeast_null_out() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);

		Assert.raises(() -> reader.tryReadAtLeast(10, null), ArgumentException);
	}

	public function test_tryReadAtLeast_invalid_count() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);

		final out = new Out();
		Assert.raises(() -> reader.tryReadAtLeast(0, out), ArgumentException);
		Assert.raises(() -> reader.tryReadAtLeast(-10, out), ArgumentException);
	}

	public function test_advance_before_read() {
		final reader = new PipeReader(new State(1024, 512));

		Assert.raises(() -> reader.advance(10, 10));
	}

	public function test_advance_invalid_consumed() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final data   = new ArrayBufferView(16);

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(data);

			if (Assert.isTrue(reader.tryRead(new Out()))) {
				Assert.raises(() -> reader.advance(-1, 0), ArgumentException);
				Assert.raises(() -> reader.advance(32, 0), ArgumentException);
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		final out = new Out();
		Assert.isFalse(state.channel.reader.tryRead(out));
	}

	public function test_advance_invalid_observed() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final data   = new ArrayBufferView(16);

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(data);

			if (Assert.isTrue(reader.tryRead(new Out()))) {
				Assert.raises(() -> reader.advance(0, -1), ArgumentException);
				Assert.raises(() -> reader.advance(0, 32), ArgumentException);
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		final out = new Out();
		Assert.isFalse(state.channel.reader.tryRead(out));
	}

	public function test_partial_consumes() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(arrayBufferViewFromBytes(src));

			final out = new Out();

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
	
				reader.advance(2, 0);
			}

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(Bytes.ofString("llo")));
	
				reader.advance(2, 0);
			}

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(Bytes.ofString("o")));
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
	}

	public function test_partial_observe_immediately_returns() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(arrayBufferViewFromBytes(src));

			final out = new Out();

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
	
				reader.advance(0, 3);
			}

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
	}

	public function test_full_observe_suspends() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(arrayBufferViewFromBytes(src));

			final out = new Out();

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
	
				reader.advance(0, src.length);
			}

			Assert.isFalse(reader.tryRead(out));
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
	}

	public function test_partial_consume_and_partial_observe() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(arrayBufferViewFromBytes(src));

			final out = new Out();

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
	
				reader.advance(2, 2);
			}

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(Bytes.ofString("llo")));
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
	}

	public function test_partial_consume_and_full_observe() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(arrayBufferViewFromBytes(src));

			final out = new Out();

			if (Assert.isTrue(reader.tryRead(out))) {
				final data = out.get();

				Assert.equals(0, data.buffer.sub(data.byteOffset, data.byteLength).compare(src));
	
				reader.advance(2, 3);
			}

			Assert.isFalse(reader.tryRead(out));
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
	}

	public function test_wakeup_suspended_writer() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final cont   = new TestContinuation();

		Assert.isTrue(state.channel.writer.tryWrite(new ArrayBufferView(1024)));
		state.count.add(1024);
		state.suspendedWriter = cont;

		final out = new Out();
		if (Assert.isTrue(reader.tryRead(out))) {
			reader.advance(1024, 0);
		}

		Assert.isTrue(cont.resumed);
		Assert.isNull(state.suspendedWriter);
	}

	public function test_dont_wakeup_suspended_writer() {
		final state  = new State(1024, 512);
		final reader = new PipeReader(state);
		final cont   = new TestContinuation();

		Assert.isTrue(state.channel.writer.tryWrite(new ArrayBufferView(1024)));
		state.count.add(1024);
		state.suspendedWriter = cont;

		final out = new Out();
		if (Assert.isTrue(reader.tryRead(out))) {
			reader.advance(100, 0);
		}

		Assert.isFalse(cont.resumed);
		Assert.notNull(state.suspendedWriter);
	}

	public function test_waitForRead_closed_writer() {
		final state      = new State(1024, 512);
		final reader     = new PipeReader(state);
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			return reader.waitForRead();
		});

		state.channel.writer.close();

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		Assert.isFalse(task.get());
	}
}