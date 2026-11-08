import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.dispatchers.TrampolineDispatcher;

/**
	Wraps a `TrampolineDispatcher` and calls `probe` before every dispatch, so that a test can
	check in which state something is dispatched, e.g. whether a lock is held.
**/
class ProbeDispatcher extends Dispatcher {
	final inner:TrampolineDispatcher;

	public var probe:Null<() -> Void>;

	public function new(inner:TrampolineDispatcher) {
		this.inner = inner;
	}

	function get_scheduler() {
		return inner.scheduler;
	}

	public function dispatch(obj:IDispatchObject) {
		if (probe != null) {
			probe();
		}
		inner.dispatch(obj);
	}
}
