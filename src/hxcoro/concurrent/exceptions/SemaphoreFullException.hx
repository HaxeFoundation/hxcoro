package hxcoro.concurrent.exceptions;

import haxe.Exception;

/**
	Thrown when releasing a semaphore whose number of available permits is already at
	its maximum.
**/
class SemaphoreFullException extends Exception {
	public function new() {
		super("Semaphore count already at maximum value");
	}
}