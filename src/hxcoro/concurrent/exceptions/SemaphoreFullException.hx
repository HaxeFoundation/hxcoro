package hxcoro.concurrent.exceptions;

import haxe.Exception;

class SemaphoreFullException extends Exception {
	public function new() {
		super("Semaphore count already at maximum value");
	}
}