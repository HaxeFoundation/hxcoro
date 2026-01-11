package hxcoro.dispatchers;

import haxe.coro.schedulers.IScheduleObject;

/**
	The dispatcher interface used by schedulers.
**/
interface IDispatcher {
	/**
		Dispatches `obj` to be executed.
	**/
	function dispatch(obj:IScheduleObject):Void;
}