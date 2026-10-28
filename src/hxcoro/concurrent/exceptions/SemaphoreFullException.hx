package hxcoro.concurrent.exceptions;

import haxe.Exception;

/**
	Thrown by `CoroSemaphore.release` (and thus `CoroMutex.release`) if the number of
	available permits is already at its maximum.
**/
class SemaphoreFullException extends Exception {
	public function new() {
		super("Semaphore count already at maximum value");
	}
}