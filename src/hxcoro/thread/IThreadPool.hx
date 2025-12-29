package hxcoro.thread;

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
	function run(task:()->Void):Void;

	/**
		Initiates a shutdown.
		All previousely submitted tasks will be executed, but no new tasks will
		be accepted.

		Multiple calls to this method have no effect.
	**/
	function shutdown():Void;
}