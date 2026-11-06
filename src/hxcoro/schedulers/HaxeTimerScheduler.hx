package hxcoro.schedulers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.Int64;
import haxe.Timer;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;

private class TimerEvent implements ISchedulerHandle implements IDispatchObject{
	final cont:IContinuation<Any>;
	var timer:Null<Timer>;
	// The part of the delay that the current timer doesn't cover yet, see `TimerDelay`.
	var remainingMs:Int64;

	public function new(ms:Int64, cont:IContinuation<Any>) {
		this.cont = cont;
		remainingMs = ms;
		timer = null;
		arm();
	}

	function arm() {
		final ms = TimerDelay.clamp(remainingMs);
		remainingMs -= ms;
		final timer = new Timer(ms);
		timer.run = run;
		this.timer = timer;
	}

	function run() {
		timer?.stop();
		if (remainingMs > 0) {
			arm();
			return;
		}
		cont.context.dispatchOrCall(this);
	}

	public function onDispatch() {
		cont.resume(null, null);
	}

	public function close() {
		timer?.stop();
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
		return new TimerEvent(ms, cont);
	}

	@:inheritDoc
	public function now() {
		return Timer.milliseconds();
	}
}