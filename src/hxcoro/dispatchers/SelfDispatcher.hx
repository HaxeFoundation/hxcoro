package hxcoro.dispatchers;

import haxe.coro.schedulers.IScheduleObject;

/**
	A dispatcher that dispatches to the current thread.
**/
class SelfDispatcher implements IDispatcher {
	/**
		Creates a new `SelfDispatcher`.
	**/
	public function new() {}

	/**
		@see `IDispatcher.dispatch`
	**/
	public function dispatch(obj:IScheduleObject) {
		obj.onSchedule();
	}

	/**
		@see `IDispatcher.shutdown
	**/
	public function shutdown() {}
}