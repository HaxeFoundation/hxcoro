package hxcoro.schedulers;

import hxcoro.dispatchers.SelfDispatcher;
import haxe.Int64;
import haxe.exceptions.ArgumentException;

class VirtualTimeScheduler extends EventLoopScheduler {
	var currentTime : Int64;

	public function new() {
		super(new SelfDispatcher());

		currentTime = 0i64;
	}

	public override function now() {
		return currentTime;
	}

	public function advanceBy(ms:Int) {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		virtualRun(currentTime + ms);
	}

	public function advanceTo(ms:Int) {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}
		if (ms < currentTime) {
			throw new ArgumentException("Cannot travel back in time");
		}

		virtualRun(ms);
	}

	function virtualRun(endTime : Int64) {
		while (true) {
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > endTime) {
				break;
			}

			final toRun = heap.extract();
			currentTime = toRun.runTime;
			toRun.onSchedule();
		}

		currentTime = endTime;
	}
}