package hxcoro.schedulers;

import haxe.Int64;
import haxe.Timer;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;

private class TimerEvent implements ISchedulerHandle {
	final timer:Timer;
	final func:() -> Void;

	public function new(ms:Int64, func:() -> Void) {
		timer = new Timer(Int64.toInt(ms));
		this.func = func;
		timer.run = run;
	}

	function run() {
		timer.stop();
		func();
	}

	public function close() {
		timer.stop();
	}
}

/**
	A scheduler based on `haxe.Timer`.
**/
class HaxeTimerScheduler extends Scheduler {
	/**
		Creates a new `HaxeTimerScheduler` instance.
	**/
	public function new() {
		super();
	}

	@:inheritDoc
	function schedule(ms:Int64, func:() -> Void) {
		return new TimerEvent(Int64.toInt(ms), func);
	}

	@:inheritDoc
	function scheduleObject(obj:IScheduleObject) {
		schedule(0, obj.onSchedule);
	}

	@:inheritDoc
	function now() {
		return Timer.milliseconds();
	}
}