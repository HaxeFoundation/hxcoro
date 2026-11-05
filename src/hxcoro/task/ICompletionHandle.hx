package hxcoro.task;

/**
	The handle of a callback registered with `ICoroTask.onCompletion`.
**/
interface ICompletionHandle {
	/**
		Unregisters the callback. Has no effect once the task has completed.
	**/
	function close():Void;
}
