package hxcoro.schedulers;

#if target.threaded
import haxe.Int64;
import haxe.Timer;
import hxcoro.concurrent.AtomicState;
import sys.thread.Condition;

private enum abstract WakeUpState(Int) to Int {
	final Unset;
	// Something changed that the loop thread has to look at, e.g. an event was scheduled.
	final Changed;
	// Like `Changed`, but the loop also has to return although it may have nothing to do.
	final WakeUpRequested;
}

/**
	A flag that tells a loop thread that it has something to do. Any thread can set it, and
	only the loop thread clears it and waits for it.
**/
class WakeUpFlag {
	final state:AtomicState<WakeUpState>;
	// Only blocks the loop thread. The state is changed without holding the mutex, but a thread
	// that moves it away from `Unset` signals while holding the mutex, and the loop thread checks
	// the state while holding it, so a waiting loop thread cannot miss the change.
	final condition:Condition;

	public function new() {
		state = new AtomicState(Unset);
		condition = new Condition();
	}

	/**
		Sets the flag. This may be called from any thread.
	**/
	public function set() {
		if (state.compareExchange(Unset, Changed) == Unset) {
			signal();
		}
	}

	/**
		Sets the flag and records that the loop has to return. This may be called from any thread.
	**/
	public function requestWakeUp() {
		if (state.exchange(WakeUpRequested) == Unset) {
			signal();
		}
	}

	function signal() {
		condition.acquire();
		condition.signal();
		condition.release();
	}

	/**
		Clears the flag without waiting and returns whether a wake-up was requested. A `set` that
		happens after this call makes the next wait return.
	**/
	public function clear() {
		return state.exchange(Unset) == WakeUpRequested;
	}

	/**
		Waits until the flag is set, then clears it and returns whether a wake-up was requested.
	**/
	public function waitAndClear() {
		condition.acquire();
		while (state.load() == Unset) {
			condition.wait();
		}
		condition.release();
		return clear();
	}

	/**
		Like `waitAndClear`, but gives up after `timeout` seconds, leaves the flag as it is and
		returns `false`.
	**/
	public function tryWaitAndClear(timeout:Float) {
		final deadline = Timer.stamp() + timeout;
		var remaining = timeout;
		condition.acquire();
		while (state.load() == Unset) {
			// `timedWait` can wake up spuriously, so wait again for the time that is left.
			if (remaining <= 0 || !condition.timedWait(remaining)) {
				condition.release();
				return false;
			}
			remaining = deadline - Timer.stamp();
		}
		condition.release();
		return clear();
	}

	/**
		Waits until the flag is set or the time `now` reaches `dueTime`, clears the flag if it was
		set, and returns whether a wake-up was requested. Without a `dueTime`, waits until the
		flag is set.
	**/
	public function waitUntil(dueTime:Null<Int64>, now:Int64) {
		if (dueTime == null) {
			return waitAndClear();
		}
		final timeout = HeapScheduler.secondsUntil(dueTime, now);
		if (timeout > 0) {
			return tryWaitAndClear(timeout);
		}
		return false;
	}
}
#end
