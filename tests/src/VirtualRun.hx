import haxe.Exception;
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

	Exceptions that escape the dispatcher are thrown out of `run`, unless `onError` is
	given. Then they are passed to `onError` and the run continues.
**/
class VirtualRun {
	static public function run<T>(lambda:NodeLambda<T>, maxTime = 1000, ?onError:(error:Exception) -> Void):ICoroTask<T> {
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task = CoroRun.with(dispatcher).createTask(lambda);
		function guard(f:() -> Void) {
			if (onError == null) {
				f();
				return;
			}
			try {
				f();
			} catch (e:Exception) {
				onError(e);
				// The trampoline keeps the objects that were queued behind the throwing one until
				// the next dispatch on this thread, so dispatch something to run them.
				guard(() -> dispatcher.dispatchFunction(() -> {}));
			}
		}
		guard(() -> task.start());
		var time = 0;
		while (task.isActive() && time < maxTime) {
			guard(() -> scheduler.advanceBy(1));
			time++;
		}
		return task;
	}
}
