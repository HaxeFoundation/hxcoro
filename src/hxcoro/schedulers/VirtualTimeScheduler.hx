package hxcoro.schedulers;

import hxcoro.schedulers.ILoop;
import haxe.Int64;
import haxe.exceptions.ArgumentException;

/**
	A scheduler with a virtual clock that starts at 0 and only advances when explicitly
	told to, which makes time-dependent code deterministic, e.g. in tests.
**/
class VirtualTimeScheduler extends HeapScheduler implements ILoop {
	var currentTime : Int64;

	public function new() {
		super();

		currentTime = 0i64;
	}

	public override function now() {
		return currentTime;
	}

	/**
		Advances the virtual time by `ms`, dispatching all events that become
		due in order of their due time. Returns `true` if there are events scheduled after
		the new time.

		Throws `haxe.exceptions.ArgumentException` if `ms` is negative.
	**/
	public function advanceBy(ms:Int) {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		return virtualRun(currentTime + ms);
	}

	/**
		Advances the virtual time to `ms`, dispatching all events that become due in order
		of their due time. Returns `true` if there are events scheduled after the new time.

		Throws `haxe.exceptions.ArgumentException` if `ms` is negative or lies before the
		current virtual time.
	**/
	public function advanceTo(ms:Int) {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}
		if (ms < currentTime) {
			throw new ArgumentException("Cannot travel back in time");
		}

		return virtualRun(ms);
	}

	function virtualRun(endTime : Int64) {
		var hasMoreEvents = false;
		while (true) {
			var minimum = heap.minimum();
			if (minimum == null) {
				break;
			} else if (minimum.runTime > endTime) {
				hasMoreEvents = true;
				break;
			}

			heap.extract();
			currentTime = minimum.runTime;
			minimum.dispatch();
		}

		currentTime = endTime;
		return hasMoreEvents;
	}

	/**
		Advances the virtual time by 1, regardless of `runMode`.
	**/
	public function loop(runMode:RunMode) {
		advanceBy(1);
	}

	public function wakeUp() {}
}