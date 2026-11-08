package hxcoro;

import haxe.exceptions.CancellationException;

/**
	Thrown when an operation does not complete within its time limit.
**/
class TimeoutException extends CancellationException {}