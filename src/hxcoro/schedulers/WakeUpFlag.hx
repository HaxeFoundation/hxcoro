package hxcoro.schedulers;

#if target.threaded
import haxe.Int64;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;
import sys.thread.Semaphore;

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

	Whenever the state isn't `Unset`, exactly one semaphore permit exists or is about to be
	released by the thread that set it. The semaphore is only there to block and to support
	timeouts.
**/
class WakeUpFlag {
	final state:AtomicState<WakeUpState>;
	// A `Condition` would be the natural thing to wait on, but it has no timed wait, which
	// the loops need for events that aren't due yet. If it gets one, this could use it instead.
	final semaphore:Semaphore;

	public function new() {
		state = new AtomicState(Unset);
		semaphore = new Semaphore(0);
	}

	/**
		Sets the flag. This may be called from any thread.
	**/
	public function set() {
		if (state.compareExchange(Unset, Changed) == Unset) {
			semaphore.release();
		}
	}

	/**
		Sets the flag and records that the loop has to return. This may be called from any thread.
	**/
	public function requestWakeUp() {
		while (true) {
			switch (state.load()) {
				case Unset:
					if (state.compareExchange(Unset, WakeUpRequested) == Unset) {
						semaphore.release();
						return;
					}
				case Changed:
					// The permit of `Changed` stays the only one.
					if (state.compareExchange(Changed, WakeUpRequested) == Changed) {
						return;
					}
				case WakeUpRequested:
					return;
			}
			BackOff.backOff();
		}
	}

	/**
		Clears the flag without waiting and returns whether a wake-up was requested. A `set` that
		happens after this call makes the next wait return.
	**/
	public function clear() {
		final old = state.exchange(Unset);
		if (old != Unset) {
			// Take the permit that belongs to the state we just undid. It has been released,
			// or is about to be.
			semaphore.acquire();
		}
		return old == WakeUpRequested;
	}

	/**
		Waits until the flag is set, then clears it and returns whether a wake-up was requested.
	**/
	public function waitAndClear() {
		semaphore.acquire();
		return state.exchange(Unset) == WakeUpRequested;
	}

	/**
		Like `waitAndClear`, but gives up after `timeout` seconds, leaves the flag as it is and
		returns `false`.
	**/
	public function tryWaitAndClear(timeout:Float) {
		if (semaphore.tryAcquire(timeout)) {
			return state.exchange(Unset) == WakeUpRequested;
		}
		return false;
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
		final timeout = Int64.toInt(dueTime - now) / 1000;
		if (timeout > 0) {
			return tryWaitAndClear(timeout);
		}
		return false;
	}
}
#end
