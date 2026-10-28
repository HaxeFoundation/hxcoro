package hxcoro.schedulers;

import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.ILoop;

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

	public function wakeUp() {}

	public function toString() {
		return '[RealTimeScheduler]';
	}
}
