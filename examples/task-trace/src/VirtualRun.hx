import hxcoro.CoroRun;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.elements.CoroName;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

/**
	Runs a task named `root` on a trampoline with a virtual clock, which makes the order of events
	deterministic, and drives the clock until the task has completed or `maxTime` virtual
	milliseconds have passed.
**/
class VirtualRun {
	static public function run<T>(lambda:NodeLambda<T>, maxTime = 1000):ICoroTask<T> {
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task = CoroRun.with(dispatcher).with(new CoroName("root")).createTask(lambda);
		task.start();
		var time = 0;
		while (task.isActive() && time < maxTime) {
			scheduler.advanceBy(1);
			time++;
		}
		return task;
	}
}
