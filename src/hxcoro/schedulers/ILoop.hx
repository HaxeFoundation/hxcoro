package hxcoro.schedulers;

/**
	Determines whether a call to `ILoop.loop` blocks if no events are ready.
**/
enum abstract RunMode(Int) {
	/**
		Processes the events that are ready. If there are none, blocks until at least
		one is ready. How exactly this waits depends on the implementation.
	**/
	final Once = 1;

	/**
		Processes the events that are ready, without blocking if there are none.
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