package hxcoro.schedulers;

import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.ILoop;
import haxe.coro.IContinuation;
import haxe.Timer;
import haxe.Int64;
import haxe.coro.Mutex;
import haxe.exceptions.ArgumentException;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;

class HeapScheduler implements IScheduler {
	final futureMutex : Mutex;
	final heap : MinimumHeap;

	public function new() {
		futureMutex  = new Mutex();
		heap         = new MinimumHeap();
	}

    public function schedule(ms:Int64, cont:IContinuation<Any>):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		final event = new ScheduledEvent(cont, now() + ms);

		futureMutex.acquire();

		heap.insert(event);

		futureMutex.release();

		return event;
    }

	public function now() {
		return Timer.milliseconds();
	}

}

class EventLoopScheduler extends HeapScheduler implements ILoop {
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
		return '[EventLoopScheduler]';
	}
}