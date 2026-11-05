package hxcoro.thread;

import haxe.coro.dispatchers.IDispatchObject;

/**
	A thread pool interface.
**/
interface IThreadPool {

	/** Amount of alive threads in this pool. */
	var threadsCount(get,never):Int;

	/** Indicates if `shutdown` method of this pool has been called. */
	var isShutDown(get,never):Bool;

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down. While it is shutting down, only tasks
		submitted from the pool's own threads are accepted.
	**/
	function run(obj:IDispatchObject):Void;

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, as well as the tasks they
		submit. Tasks from other threads are rejected.

		If `block == true`, the calling thread blocks until all threads in the pool
		have shut down, which includes running the tasks that the pool's tasks keep
		submitting.

		Multiple calls to this method have no effect.

		The pool must outlive every coroutine task that dispatches to it. Shutting it
		down while such a task is still active leaves the task stranded: continuations
		that are dispatched after the shutdown completed are rejected with an exception,
		and a loop that waits for the task (e.g. via `hxcoro.run.LoopRun`) may block
		forever if nothing else wakes it up. Wait for the task to complete before
		shutting down the pool.
	**/
	function shutDown(block:Bool = false):Void;
}