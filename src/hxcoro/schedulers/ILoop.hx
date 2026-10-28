package hxcoro.schedulers;

/**
	Determines how long a call to `ILoop.loop` may run.
**/
enum abstract RunMode(Int) {
	/**
		Processes pending events, waiting for at least one if none are ready.
		The exact waiting behavior depends on the implementation.
	**/
	final Once = 1;

	/**
		Processes the events that are ready and returns without waiting.
	**/
	final NoWait = 2;
}

/**
	A scheduler or event loop that is driven by explicitly calling `loop`, e.g.
	via `hxcoro.run.LoopRun`.
**/
interface ILoop {
	/**
		Runs one iteration of the loop, dispatching due events according to `runMode`.
	**/
	function loop(runMode:RunMode):Void;

	/**
		Wakes up a `loop` call that is waiting for events, so that it can return.
		This may be called from any thread. Implementations that never wait may
		do nothing.
	**/
	function wakeUp():Void;
}