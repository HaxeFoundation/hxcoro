package hxcoro.dispatchers;

import haxe.coro.dispatchers.IDispatchObject;

/**
	The dispatcher interface used by schedulers.
**/
interface IDispatcher {
	/**
		Dispatches `obj` to be executed.
	**/
	function dispatch(obj:IDispatchObject):Void;
}