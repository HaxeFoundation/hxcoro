package hxcoro.schedulers;

#if target.threaded
import haxe.Int64;
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
		Waits until the flag is set or the time `now` reaches `dueTime`, then clears the flag and
		returns whether a wake-up was requested. Without a `dueTime`, waits until the flag is set.

		This may return earlier, so the caller has to check what it waits for and call it again.
	**/
	public function waitUntil(dueTime:Null<Int64>, now:Int64) {
		final timeout = dueTime == null ? null : HeapScheduler.secondsUntil(dueTime, now);
		if (timeout == null || timeout > 0) {
			condition.acquire();
			if (state.load() == Unset) {
				// Spurious wake-ups and timeouts cut short by the target just make the caller
				// look again, like any other early return.
				if (timeout == null) {
					condition.wait();
				} else {
					condition.timedWait(timeout);
				}
			}
			condition.release();
		}
		return clear();
	}
}
#end
