package hxcoro.task;

import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.ThreadSafeCallbacks;

private enum abstract HandleState(Int) to Int {
	final Open;
	final Closed;
}

/**
	A cancellation callback registered with a task via `TaskCancellationManager`.
**/
class CancellationHandle implements ICancellationHandle {
	final callback:ICancellationCallback;
	final manager:TaskCancellationManager;
	var closed:AtomicState<HandleState>;

	public function new(callback, manager) {
		this.callback = callback;
		this.manager = manager;
		closed = new AtomicState(Open);
	}

	/**
		Invokes the callback with `task`'s cancellation cause, unless this handle has already run or been closed.
	**/
	public function run(task:AbstractTask) {
		if (closed.compareExchange(Open, Closed) != Open) {
			return;
		}

		final error = task.getError();
		callback.onCancellation(error.orCancellationException());
	}

	public function close() {
		if (closed.compareExchange(Open, Closed) == Open) {
			manager.remove(this);
		}
	}
}

/**
	Holds the cancellation callbacks registered with a task and runs them once the task is cancelled.
**/
class TaskCancellationManager extends ThreadSafeCallbacks<ICancellationCallback, CancellationHandle, ICancellationHandle> {
	public function new(task:AbstractTask) {
		super(handle -> handle.run(task));
	}

	function createHandle(element:ICancellationCallback) {
		return new CancellationHandle(element, this);
	}
}