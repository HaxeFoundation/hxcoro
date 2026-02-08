package hxcoro.schedulers;

import haxe.Int64;
import haxe.exceptions.ArgumentException;

class VirtualTimeScheduler extends EventLoopScheduler.HeapScheduler implements ILoop {
	var currentTime : Int64;

	public function new() {
		super();

		currentTime = 0i64;
	}

	public override function now() {
		return currentTime;
	}

	public function advanceBy(ms:Int) {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		return virtualRun(currentTime + ms);
	}

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

	public function loop() {
		while (advanceBy(1)) {}
	}
}