package hxcoro.thread;

import haxe.Exception;

/**
	Exception thrown by thread pools, e.g. when a task is submitted to a pool that has been shut down.
**/
class ThreadPoolException extends Exception {}