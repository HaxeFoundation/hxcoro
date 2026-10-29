import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;

/**
	Runs a task on a `TrampolineDispatcher` with a `VirtualTimeScheduler` and drives the
	virtual clock from the calling code.

	This makes interleavings deterministic: a resumption that is dispatched while the
	trampoline is busy runs only after the current frame returns, so code in that frame
	can act inside the window that another thread would hit on a thread pool.

	This never blocks. If the task is still active after `maxTime` virtual milliseconds,
	it is returned in that state, so tests can assert on it instead of hanging.
**/
class VirtualRun {
	static public function run<T>(lambda:NodeLambda<T>, maxTime = 1000):ICoroTask<T> {
		final scheduler = new VirtualTimeScheduler();
		final task = CoroRun.with(new TrampolineDispatcher(scheduler)).createTask(lambda);
		task.start();
		var time = 0;
		while (task.isActive() && time < maxTime) {
			scheduler.advanceBy(1);
			time++;
		}
		return task;
	}
}
