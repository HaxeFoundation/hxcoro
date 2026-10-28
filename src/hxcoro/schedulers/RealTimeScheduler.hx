package hxcoro.schedulers;

import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.ILoop;

/**
	A scheduler driven by `loop` calls that dispatches events based on the time returned
	by `haxe.Timer.milliseconds`.
**/
class RealTimeScheduler extends HeapScheduler implements ILoop {
	function loopOnce() {
		final currentTime = now();
		var didSomething = false;
		while (true) {
			futureMutex.acquire();
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				break;
			}

			heap.extract();
			futureMutex.release();

			didSomething = true;
			minimum.dispatch();
		}

		futureMutex.release();
		return didSomething;
	}

	/**
		Dispatches the events that are due. In `Once` mode, this busy-waits with back-off
		until at least one event has been dispatched.
	**/
	public function loop(runMode:RunMode) {
		switch (runMode) {
			case NoWait:
				loopOnce();
			case Once:
				while (!loopOnce()) {
					BackOff.backOff();
				}
		}
	}

	/**
		Has no effect, because `loop` busy-waits instead of blocking.
	**/
	public function wakeUp() {}

	/**
		Returns a string representation of this scheduler.
	**/
	public function toString() {
		return '[RealTimeScheduler]';
	}
}
