package hxcoro.concurrent;

import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;

enum abstract CallbacksState(Int) to Int {
	final Ready;
	final Modifying;
	final Finished;
}

abstract class ThreadSafeCallbacks<Element, HandleIn : HandleOut, HandleOut> {
	var handles:Null<Array<HandleIn>>;
	final execute:HandleIn -> Void;
	final state:AtomicState<CallbacksState>;

	function new(execute:HandleIn -> Void) {
		handles = null;
		this.execute = execute;
		state = new AtomicState(Ready);
	}

	// single threaded

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
			execute(handle);
		}
	}

	// thread-safe

	abstract function createHandle(element:Element):HandleIn;

	public function add(element:Element):Null<HandleOut> {
		final handle = createHandle(element);
		while (true) {
			switch (state.compareExchange(Ready, Modifying)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					execute(handle);
					return null;
			}
		}
		handles ??= [];
		handles.push(handle);
		state.store(Ready);
		return handle;
	}

	public function remove(handle:HandleIn) {
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