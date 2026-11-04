package hxcoro.exceptions;

import haxe.Exception;

/**
	Thrown when an operation is not allowed in a task's current state, for example a second
	concurrent `awaitChildren` call on the same task.
**/
class InvalidTaskStateException extends Exception {}
