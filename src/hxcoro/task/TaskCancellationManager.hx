package hxcoro.task;

import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;
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

private enum abstract ManagerState(Int) to Int {
	final Ready;
	final Modifying;
	final Finished;
}

class TaskCancellationManager {
	public final task:AbstractTask;
	final state:AtomicState<ManagerState>;
	var handles:Null<Array<CancellationHandle>>;

	public function new(task:AbstractTask) {
		this.task = task;
		handles = null;
		state = new AtomicState(Ready);
	}

	// single-threaded

	public function run() {
		while (true) {
			switch (state.compareExchange(Ready, Finished)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					// already done
					return;
			}
		}
		final handles = handles;
		if (handles == null) {
			return;
		}
		this.handles = null;
		for (handle in handles) {
			// TODO: should we catch errors from the callbacks here?
			handle.run();
		}

	}

	// thread-safe

	public function addCallback(callback:ICancellationCallback):ICancellationHandle {
		final handle = new CancellationHandle(callback, this);
		while (true) {
			switch (state.compareExchange(Ready, Modifying)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					handle.run();
					return CancellationHandle.noOpCancellationHandle;
			}
		}
		handles ??= [];
		handles.push(handle);
		state.store(Ready);
		return handle;
	}

	public function remove(handle:CancellationHandle) {
		while (true) {
			switch (state.compareExchange(Ready, Modifying)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					// already cleared, nothing to do
					return;
			}
		}
		if (handles != null) {
			handles.remove(handle);
		}
		state.store(Ready);
	}
}