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
		final numChildrenHalved = 500;
		final numChildren = numChildrenHalved * 2;

		final task = CoroRun.with(dispatcher).createTask(node -> {
			var k = 0;
			for (i in 0...numChildren) {
				node.async(_ -> {
					delay(i & 1 == 0 ? 5 : 10);
					k++;
				});
			}
			delay(11);
			k;
		});
		task.start();
		final atask:AbstractTask = cast task;

		scheduler.advanceTo(5);

		final children = @:privateAccess atask.getCurrentChildren();
		Assert.equals(numChildrenHalved, children.length);

		scheduler.advanceTo(10);

		final children = @:privateAccess atask.getCurrentChildren();
		Assert.equals(0, children.length);

		scheduler.advanceTo(11);
		Assert.equals(numChildren, task.get());
	}
}