package hxcoro.task;

import haxe.Exception;
import haxe.exceptions.CancellationException;

/**
	The `CancellationException` caused by a task failing with `error`.
**/
class FailureCancellationException extends CancellationException {
	/**
		The error the task failed with.
	**/
	public final error:Exception;

	public function new(error:Exception) {
		super();
		this.error = error;
	}
}
