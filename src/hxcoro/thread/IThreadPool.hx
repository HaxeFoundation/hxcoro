package hxcoro.thread;

import haxe.coro.schedulers.IScheduleObject;

/**
	A thread pool interface.
**/
interface IThreadPool {

	/** Amount of alive threads in this pool. */
	var threadsCount(get,never):Int;

	/** Indicates if `shutdown` method of this pool has been called. */
	var isShutdown(get,never):Bool;

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down.
	**/
	function run(obj:IScheduleObject):Void;

	/**
		Initiates a shutdown.
		All previousely submitted tasks will be executed, but no new tasks will
		be accepted.

		If `block == true`, the calling thread blocks until all threads in the pool
		have shut down.

		Multiple calls to this method have no effect.
	**/
	function shutdown(block:Bool = false):Void;
}