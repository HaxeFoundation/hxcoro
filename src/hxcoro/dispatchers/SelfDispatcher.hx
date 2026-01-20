package hxcoro.dispatchers;

import haxe.coro.dispatchers.IDispatchObject;

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
	public function dispatch(obj:IDispatchObject) {
		obj.onDispatch();
	}
}