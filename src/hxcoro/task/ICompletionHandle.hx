package hxcoro.task;

/**
	The handle of a callback registered with `ICoroTask.onCompletion`.
**/
interface ICompletionHandle {
	/**
		Unregisters the callback, so that it does not run when the task completes. Has no effect
		if the task has already completed. This function is thread safe and may be called more
		than once.
	**/
	function close():Void;
}
