package hxcoro.schedulers;

#if target.threaded
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
	A flag that tells a loop thread that it has something to do. Any thread can change it, and
	only the loop thread resets it and waits for it.
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
		Records that something changed that the loop thread has to look at. This may be called
		from any thread.
	**/
	public function markChanged() {
		if (state.compareExchange(Unset, Changed) == Unset) {
			signal();
		}
	}

	/**
		Records that something changed and that the loop has to return. This may be called from
		any thread.
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
		Resets the flag and returns whether a wake-up was requested since the last reset.
	**/
	public function takeWakeUpRequest() {
		// A change recorded after this exchange makes the next wait return.
		return state.exchange(Unset) == WakeUpRequested;
	}

	/**
		Blocks until a change is recorded or `timeout` seconds have passed. Without a `timeout`,
		blocks until a change is recorded. Returns immediately if a change was recorded since the
		last reset. Doesn't reset the flag.

		This may return earlier, so the caller has to check what it waits for and wait again.
	**/
	public function waitForChange(timeout:Null<Float>) {
		if (timeout != null && timeout <= 0) {
			return;
		}
		condition.acquire();
		if (state.load() == Unset) {
			// Spurious wake-ups and timeouts cut short by the target just make the caller look
			// again, like any other early return.
			if (timeout == null) {
				condition.wait();
			} else {
				condition.timedWait(timeout);
			}
		}
		condition.release();
	}
}
#end
