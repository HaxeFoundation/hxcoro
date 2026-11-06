package hxcoro.schedulers;

import haxe.Int64;
import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.ILoop;

/**
	A scheduler driven by `loop` calls that dispatches events based on the time returned
	by `haxe.Timer.milliseconds`.
**/
class RealTimeScheduler extends HeapScheduler implements ILoop {
	#if target.threaded
	final wakeUpFlag:WakeUpFlag;
	#end
	// The due time of the earliest event that `loopOnce` left in the heap. Only used by the loop
	// thread. An event that is scheduled later sets the wake-up flag, so this may be outdated.
	var nextDueTime:Null<Int64>;

	public function new() {
		super();
		nextDueTime = null;
		#if target.threaded
		wakeUpFlag = new WakeUpFlag();
		#end
	}

	function eventScheduled(event:ScheduledEvent) {
		#if target.threaded
		// The event may be due before the one the loop is waiting for.
		wakeUpFlag.set();
		#end
	}

	function loopOnce() {
		final currentTime = now();
		var didSomething = false;
		while (true) {
			futureMutex.acquire();
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				nextDueTime = minimum?.runTime;
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
		Dispatches the events that are due. In `Once` mode, if no event is due, this blocks until
		an event has been dispatched or `wakeUp` is called.

		This must not be called from multiple threads at the same time.
	**/
	public function loop(runMode:RunMode) {
		switch (runMode) {
			case NoWait:
				loopOnce();
			case Once:
				#if target.threaded
				var wokenUp = false;
				#end
				while (true) {
					#if target.threaded
					// Clear the flag before looking at the heap. An event scheduled or a wake-up
					// requested from now on sets it again, so the wait below can't miss it.
					if (wakeUpFlag.clear()) {
						wokenUp = true;
					}
					if (loopOnce() || wokenUp) {
						return;
					}
					wokenUp = wakeUpFlag.waitUntil(nextDueTime, now());
					#else
					if (loopOnce()) {
						return;
					}
					wait();
					#end
				}
		}
	}

	#if !target.threaded
	// Nothing can schedule an event while the loop waits, so it can sleep until the earliest one
	// is due. Without `Sys.sleep`, or without any event, this busy-waits.
	function wait() {
		#if (sys && !lua_vanilla)
		final dueTime = nextDueTime;
		if (dueTime != null) {
			final timeout = HeapScheduler.secondsUntil(dueTime, now());
			if (timeout > 0) {
				Sys.sleep(timeout);
			}
			return;
		}
		#end
		BackOff.backOff();
	}
	#end

	/**
		Makes the current or next `loop(Once)` call return. This may be called from any thread.
		Has no effect on targets without threads.
	**/
	public function wakeUp() {
		#if target.threaded
		wakeUpFlag.requestWakeUp();
		#end
	}

	/**
		Returns a string representation of this scheduler.
	**/
	public function toString() {
		return '[RealTimeScheduler]';
	}
}
