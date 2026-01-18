package hxcoro.task;

import haxe.coro.Mutex;
import hxcoro.concurrent.AtomicState;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;

private class NoOpCancellationHandle implements ICancellationHandle {
	public function new() {}

	public function close() {}
}

private enum abstract HandleState(Int) to Int {
	final Open;
	final Closed;
}

class CancellationHandle implements ICancellationHandle {

	static public final noOpCancellationHandle = new NoOpCancellationHandle();

	final callback:ICancellationCallback;
	final manager:TaskCancellationManager;
	var closed:AtomicState<HandleState>;

	public function new(callback, manager) {
		this.callback = callback;
		this.manager = manager;
		closed = new AtomicState(Open);
	}

	public function run() {
		if (closed.compareExchange(Open, Closed) != Open) {
			return;
		}

		final error = manager.task.getError();
		callback.onCancellation(error.orCancellationException());
	}

	public function close() {
		if (closed.compareExchange(Open, Closed) == Open) {
			manager.remove(this);
		}
	}
}

class TaskCancellationManager {
	public final task:AbstractTask;
	final mutex:Mutex;

	var handles:Array<CancellationHandle>;

	public function new(task:AbstractTask) {
		this.task = task;
		this.mutex = new Mutex();
		handles = [];
	}

	// single-threaded

	public function run() {
		for (handle in handles) {
			// TODO: should we catch errors from the callbacks here?
			handle.run();
		}

	}

	// thread-safe

	public function addCallback(callback:ICancellationCallback) {
		final handle = new CancellationHandle(callback, this);
		mutex.acquire();
		handles.push(handle);
		mutex.release();
		return handle;
	}

	public function remove(handle:CancellationHandle) {
		mutex.acquire();
		handles.remove(handle);
		mutex.release();
	}
}