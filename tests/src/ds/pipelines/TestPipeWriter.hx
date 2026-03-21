package ds.pipelines;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.io.Bytes;
import hxcoro.ds.Out;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.pipelines.pipe.State;
import hxcoro.ds.pipelines.pipe.PipeWriter;
import atest.Test;

class TestPipeWriter extends Test {
	function test_getBuffer() {
		final writer = new PipeWriter(new State(1024, 512));
		final buffer = writer.getBuffer();

		Assert.isTrue(buffer.byteLength > 0);
	}

	function test_getBuffer_minimumSize() {
		final writer = new PipeWriter(new State(1024, 512));
		final size   = 64_000;
		final buffer = writer.getBuffer(size);

		Assert.isTrue(buffer.byteLength >= size);
	}

	function test_getBuffer_invalid_minimumSize() {
		final writer = new PipeWriter(new State(1024, 512));

		Assert.raises(() -> writer.getBuffer(-1), ArgumentException);
	}

	function test_getBuffer_again_before_returning() {
		final writer = new PipeWriter(new State(1024, 512));
		final _      = writer.getBuffer();

		Assert.raises(() -> writer.getBuffer());
	}

	function test_advancing_buffer() {
		final writer = new PipeWriter(new State(1024, 512));
		final size   = 16;
		final _      = writer.getBuffer(size);

		writer.advance(8);

		Assert.pass();
	}

	function test_advancing_buffer_invalid_size() {
		final writer = new PipeWriter(new State(1024, 512));
		final size   = 16;
		final _      = writer.getBuffer(size);

		Assert.raises(() -> writer.advance(-1), ArgumentException);
		Assert.raises(() -> writer.advance(size * 2), ArgumentException);
	}

	function test_advancing_buffer_twice() {
		final writer = new PipeWriter(new State(1024, 512));
		final size   = 16;
		final _      = writer.getBuffer(size);

		writer.advance(8);

		Assert.raises(() -> writer.advance(8));
	}

	function test_advance_with_no_buffer() {
		final writer = new PipeWriter(new State(1024, 512));

		Assert.raises(() -> writer.advance(8));
	}

	function test_flush_single_write() {
		final state  = new State(1024, 512);
		final writer = new PipeWriter(state);
		final data   = Bytes.ofString("Hello");

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			final size   = 16;
			final view = writer.getBuffer(size);
			view.buffer.blit(view.byteOffset, data, 0, data.length);

			writer.advance(data.length);
			writer.flush();
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());

		final out = new Out();
		if (Assert.isTrue(state.channel.reader.tryRead(out))) {
			final read = out.get();

			Assert.equals(data.length, out.get().byteLength);
			Assert.equals(0, read.buffer.sub(read.byteOffset, read.byteLength).compare(data));

			Assert.isFalse(state.channel.reader.tryRead(out));
		}
	}

	function test_flush_multi_write() {
		final state  = new State(1024, 512);
		final writer = new PipeWriter(state);

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			final size = 16;

			final view = writer.getBuffer(size);
			final data = Bytes.ofString("Hello");
			view.buffer.blit(view.byteOffset, data, 0, data.length);
			writer.advance(data.length);

			final view = writer.getBuffer(size);
			final data = Bytes.ofString("World");
			view.buffer.blit(view.byteOffset, data, 0, data.length);
			writer.advance(data.length);

			writer.flush();
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());

		final out = new Out();
		if (Assert.isTrue(state.channel.reader.tryRead(out))) {
			final read = out.get();

			Assert.equals(0, read.buffer.sub(read.byteOffset, read.byteLength).compare(Bytes.ofString("Hello")));

			if (Assert.isTrue(state.channel.reader.tryRead(out))) {
				final read = out.get();

				Assert.equals(0, read.buffer.sub(read.byteOffset, read.byteLength).compare(Bytes.ofString("World")));

				Assert.isFalse(state.channel.reader.tryRead(out));
			}
		}
	}

	function test_suspending_flush() {
		final state  = new State(1024, 512);
		final writer = new PipeWriter(state);
		final data   = Bytes.alloc(16_000);

		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			final view = writer.getBuffer(data.length);
			view.buffer.blit(view.byteOffset, data, 0, data.length);

			writer.advance(data.length);
			writer.flush();
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isTrue(task.isActive());

		final out = new Out();
		if (Assert.isTrue(state.channel.reader.tryRead(out))) {
			final read = out.get();

			Assert.equals(0, read.buffer.sub(read.byteOffset, read.byteLength).compare(data));

			Assert.isFalse(state.channel.reader.tryRead(out));
		}

		Assert.notNull(state.suspendedWriter);
	}
}