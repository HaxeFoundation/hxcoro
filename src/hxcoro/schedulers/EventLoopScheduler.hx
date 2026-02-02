package hxcoro.schedulers;

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
	public function loop(loopMode:LoopMode) {
		var didDispatch = false;

		while (true) {
			final currentTime = now();
			var hasMoreEvents = false;
			while (true) {
				futureMutex.acquire();
				var minimum = heap.minimum();
				if (minimum == null) {
					break;
				}
				if (minimum.isRemovable()) {
					heap.extract();
					futureMutex.release();
					continue;
				}
				if (minimum.runTime > currentTime) {
					hasMoreEvents = true;
					break;
				}

				final toRun = heap.extract();
				futureMutex.release();

				didDispatch = true;
				toRun.dispatch();
			}

			futureMutex.release();

			switch (loopMode) {
				case Default if (hasMoreEvents):
					continue;
				case Once if (!didDispatch):
					continue;
				case _:
					return hasMoreEvents ? 1 : 0;
			}
		}
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}
}