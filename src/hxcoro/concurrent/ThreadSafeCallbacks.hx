package hxcoro.concurrent;

import haxe.Exception;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;

/**
	The internal state of a `ThreadSafeCallbacks` instance.
**/
enum abstract CallbacksState(Int) to Int {
	final Ready;
	final Modifying;
	final Finished;
}

/**
	Base class for a thread-safe collection of callbacks that are executed once when
	`run` is called.

	A callback that throws doesn't affect the others: its exception is passed to the `onError`
	function given to the constructor, and the remaining callbacks still run. The callbacks are
	often other tasks' continuations, so stopping at the first exception would leave those tasks
	waiting forever.
**/
abstract class ThreadSafeCallbacks<Element, HandleIn : HandleOut, HandleOut> {
	var handles:Null<Array<HandleIn>>;
	final execute:HandleIn -> Void;
	final onError:Exception -> Void;
	final state:AtomicState<CallbacksState>;

	function new(execute:HandleIn -> Void, onError:Exception -> Void) {
		handles = null;
		this.execute = execute;
		this.onError = onError;
		state = new AtomicState(Ready);
	}

	function invoke(handle:HandleIn) {
		try {
			execute(handle);
		} catch (e:Exception) {
			onError(e);
		}
	}

	// single threaded

	/**
		Executes all registered callbacks. Subsequent calls have no effect.
	**/
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
			invoke(handle);
		}
	}

	// thread-safe

	abstract function createHandle(element:Element):HandleIn;

	/**
		Registers `element` and returns its handle. If `run` has already been called, the
		callback is executed immediately and `null` is returned instead.
	**/
	public function add(element:Element):Null<HandleOut> {
		final handle = createHandle(element);
		while (true) {
			switch (state.compareExchange(Ready, Modifying)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					invoke(handle);
					return null;
			}
		}
		handles ??= [];
		handles.push(handle);
		state.store(Ready);
		return handle;
	}

	/**
		Unregisters `handle`. Has no effect if `run` has already been called.
	**/
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