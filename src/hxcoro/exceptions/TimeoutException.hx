package hxcoro.exceptions;

import haxe.exceptions.CancellationException;

/**
	Thrown by `Coro.timeout` when the timeout elapses before the lambda completes.
**/
class TimeoutException extends CancellationException {}