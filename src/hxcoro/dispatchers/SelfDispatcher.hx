package hxcoro.dispatchers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;

/**
	A dispatcher that dispatches to the current thread.
**/
class SelfDispatcher extends Dispatcher {

	final s:IScheduler;

	/**
		Creates a new `SelfDispatcher`.
	**/
	public function new(scheduler:IScheduler) {
		s = scheduler;
	}

	function get_scheduler() {
		return s;
	}

	/**
		@see `IDispatcher.dispatch`
	**/
	public function dispatch(obj:IDispatchObject) {
		obj.onDispatch();
	}
}