package issues.aidan;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.CoroRun;
import hxcoro.Coro.*;
import hxcoro.task.AbstractTask;

class Issue106 extends atest.Test {
	public function test() {
		final scheduler   = new VirtualTimeScheduler();
		final dispatcher  = new TrampolineDispatcher(scheduler);
		final numChildrenHalved = 500;
		final numChildren = numChildrenHalved * 2;

		final task = CoroRun.with(dispatcher).createTask(node -> {
			var k = 0;
			for (i in 0...numChildren) {
				node.async(_ -> {
					delay(i & 1 == 1 ? 5 : 10);
					k++;
				});
			}
			delay(11);
			k;
		});
		task.start();
		final atask:AbstractTask = cast task;

		scheduler.advanceTo(5);

		Assert.equals(numChildrenHalved, @:privateAccess atask.numActiveChildren.load());

		scheduler.advanceTo(10);

		Assert.equals(0, @:privateAccess atask.numActiveChildren.load());

		scheduler.advanceTo(11);
		Assert.equals(numChildren, task.get());
	}
}