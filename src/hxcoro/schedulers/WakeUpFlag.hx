package hxcoro.schedulers;

#if target.threaded
import haxe.Int64;
import haxe.atomic.AtomicInt;
import sys.thread.Semaphore;

/**
	A flag that tells a loop thread that it has something to do. Any thread can set it, and
	only the loop thread clears it and waits for it.

	Whenever `isSet` is 1, exactly one semaphore permit exists or is about to be released by
	the thread that set it. The semaphore is only there to block and to support timeouts.
**/
class WakeUpFlag {
	final isSet:AtomicInt;
	// A `Condition` would be the natural thing to wait on, but it has no timed wait, which
	// the loops need for events that aren't due yet. If it gets one, this could use it instead.
	final semaphore:Semaphore;

	public function new() {
		isSet = new AtomicInt(0);
		semaphore = new Semaphore(0);
	}

	/**
		Sets the flag. This may be called from any thread.
	**/
	public function set() {
		if (isSet.compareExchange(0, 1) == 0) {
			semaphore.release();
		}
	}

	/**
		Clears the flag without waiting. A `set` that happens after this call makes the next
		wait return.
	**/
	public function clear() {
		if (isSet.exchange(0) == 1) {
			// Take the permit that belongs to the `set` we just undid. It has been released,
			// or is about to be.
			semaphore.acquire();
		}
	}

	/**
		Waits until the flag is set, then clears it.
	**/
	public function waitAndClear() {
		semaphore.acquire();
		isSet.store(0);
	}

	/**
		Like `waitAndClear`, but gives up after `timeout` seconds and leaves the flag as it is.
	**/
	public function tryWaitAndClear(timeout:Float) {
		if (semaphore.tryAcquire(timeout)) {
			isSet.store(0);
		}
	}

	/**
		Waits until the flag is set or the time `now` reaches `dueTime`, then clears the flag if it
		was set. Without a `dueTime`, waits until the flag is set.
	**/
	public function waitUntil(dueTime:Null<Int64>, now:Int64) {
		if (dueTime == null) {
			waitAndClear();
			return;
		}
		final timeout = Int64.toInt(dueTime - now) / 1000;
		if (timeout > 0) {
			tryWaitAndClear(timeout);
		}
	}
}
#end
