package ds.pipelines;

import haxe.io.ArrayBufferView;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.io.Bytes;
import hxcoro.ds.Out;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.pipelines.Pipe.State;
import hxcoro.ds.pipelines.PipeReader;
import atest.Test;

class TestPipeReader extends Test {
	public function test_tryRead() {
		final state  = new State();
		final reader = new PipeReader(state);
		final data   = new ArrayBufferView(16);

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(data);

			final out = new Out();
			if (Assert.isTrue(reader.tryRead(out))) {
				Assert.equals(out.get().byteLength, out.get().byteLength);
			}
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		final out = new Out();
		Assert.isFalse(state.channel.reader.tryRead(out));
	}

	public function test_advance_before_read() {
		final reader = new PipeReader(new State());

		Assert.raises(() -> reader.advance(10, 10));
	}

	public function test_advance_invalid_consumed() {
		final state  = new State();
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
		final state  = new State();
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
		final state  = new State();
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(ArrayBufferView.fromBytes(src));

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
		final state  = new State();
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(ArrayBufferView.fromBytes(src));

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
		final state  = new State();
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(ArrayBufferView.fromBytes(src));

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
		final state  = new State();
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(ArrayBufferView.fromBytes(src));

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
		final state  = new State();
		final reader = new PipeReader(state);
		final src    = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			state.channel.writer.write(ArrayBufferView.fromBytes(src));

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
}