package issues.aidan;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.CoroRun;
import hxcoro.Coro.*;
import hxcoro.task.AbstractTask;

class Issue106 extends utest.Test {
	public function test() {
		final scheduler   = new VirtualTimeScheduler();
		final dispatcher  = new TrampolineDispatcher(scheduler);
		final numChildren = 1000;

		final task = CoroRun.with(dispatcher).create(node -> {
			var k = 0;
			for (_ in 0...numChildren) {
				node.async(_ -> {
					// https://github.com/Aidan63/haxe/issues/98 prevents writing a test utilizing loop variables
					delay(Math.random() > 0.5 ? 5 : 10);
					k++;
				});
			}
			delay(11);
			k;
		});
		task.start();
		final atask:AbstractTask = cast task;

		scheduler.advanceTo(5);

		atask.iterateChildren(child -> {
			Assert.isTrue(child.isActive());
		});

		scheduler.advanceTo(10);

		var count = 0;
		atask.iterateChildren(child -> {
			count++;
		});

		Assert.equals(0, count);

		scheduler.advanceTo(11);
		Assert.equals(numChildren, task.get());
	}
}