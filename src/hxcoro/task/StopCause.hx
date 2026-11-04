package hxcoro.task;

import haxe.Exception;
import haxe.exceptions.CancellationException;

/**
	Why a task stopped, or is stopping. It is recorded when cancellation is requested or a failure
	happens, before the task's state changes, and the state decides when it is visible.

	A `Cancellation` can be upgraded to a `Failure` if a failure happens while the task is
	cancelling. A `Failure` is never replaced; later failures are kept as suppressed errors.
**/
enum StopCause {
	/**
		Cancellation was requested with `cause`, which is also what the task's children are
		cancelled with.
	**/
	Cancellation(cause:CancellationException);

	/**
		The task's own work or one of its children failed with `error`. `cause` is what the task's
		children are cancelled with and what cancellation callbacks receive.
	**/
	Failure(error:Exception, cause:CancellationException);
}
