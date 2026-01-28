package hxcoro.schedulers;

import haxe.Int64;
import haxe.Timer;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;

private class TimerEvent implements ISchedulerHandle {
	final timer:Timer;
	final cont:IContinuation<Any>;

	public function new(ms:Int64, cont:IContinuation<Any>) {
		timer = new Timer(Int64.toInt(ms));
		this.cont = cont;
		timer.run = run;
	}

	function run() {
		timer.stop();
		cont.resume(null, null);
	}

	public function close() {
		timer.stop();
	}
}

/**
	A scheduler based on `haxe.Timer`.
**/
class HaxeTimerScheduler implements IScheduler {
	/**
		Creates a new `HaxeTimerScheduler` instance.
	**/
	public function new() {}

	@:inheritDoc
	public function schedule(ms:Int64, cont:IContinuation<Any>) {
		return new TimerEvent(Int64.toInt(ms), cont);
	}

	@:inheritDoc
	public function now() {
		return Timer.milliseconds();
	}
}