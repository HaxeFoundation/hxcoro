package ds.pipelines;

import haxe.io.Bytes;
import atest.Test;
import hxcoro.ds.Out;
import hxcoro.ds.pipelines.pipe.State;
import hxcoro.ds.pipelines.pipe.PipeWriter;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;

using hxcoro.ds.pipelines.PipeExtensions;

class TestPipeExtensions extends Test {
	function test_write() {
		final data       = Bytes.ofString("Hello, World!");
		final state      = new State(1024, 512);
		final writer     = new PipeWriter(state);
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			writer.write(data);
		});

		task.start();
		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());

		final out = new Out();
		if (Assert.isTrue(state.channel.reader.tryRead(out))) {
			final read = out.get();
			Assert.equals(0, read.buffer.sub(read.byteOffset, read.byteLength).compare(data));
		}
	}
}