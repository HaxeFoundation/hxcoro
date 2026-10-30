package hxcoro.concurrent;

import haxe.coro.IContinuation;
import haxe.exceptions.ArgumentException;
import hxcoro.concurrent.exceptions.SemaphoreFullException;
import hxcoro.ds.PagedDeque;
import haxe.atomic.AtomicInt;

/**
	A counting semaphore for coroutines that limits concurrent access to a resource
	to a number of permits. Coroutines waiting in `acquire` are resumed in the order
	in which they started waiting.
**/
class CoroSemaphore {
	@:nullSafety(Off) final maxFree:Int;
	var deque:PagedDeque<IContinuation<Any>>;
	var free:AtomicInt;

	/**
		Creates a new `CoroSemaphore` instance with `free` initially available permits.

		`maxFree` is the maximum number of permits and defaults to `free`, so it has to be
		set if the semaphore starts without any free permits. An `ArgumentException` is
		thrown if `free` is negative, if `maxFree` is less than 1, or if `free` exceeds
		`maxFree`.
	**/
	@:nullSafety(Off)
	public function new(free:Int, ?maxFree:Int) {
		if (free < 0) {
			throw new ArgumentException("free", "Value of free must be >= 0");
		}
		if (maxFree == null) {
			if (free == 0) {
				throw new ArgumentException("maxFree", "If free is 0, maxFree must be set");
			}
			this.maxFree = free;
		} else if (maxFree < 1) {
			throw new ArgumentException("maxFree", "Maximum free count must be greater than 1");
		} else if (free > maxFree) {
			throw new ArgumentException("free", "Value of free must be <= maxFree");
		} else {
			this.maxFree = maxFree;
		}

		this.free = new AtomicInt(free);
		deque = new PagedDeque();
	}

	/**
		Acquires a permit, suspending until one becomes available if necessary.
	**/
	@:coroutine public function acquire() {
		// CAS loop until we update the free atomic or it reports full.
		while (true) {
			final old = free.load();
			if (old < 0) {
				// Someone has the "mutex", let's wait
				BackOff.backOff();
				continue;
			}
			if (free.compareExchange(old, old - 1) == old) {
				if (old == 0) {
					// The value is -1 now, so we have the mutex and can suspend.
					break;
				} else {
					// Normal acquire
					return;
				}
			}
		}
		// If we get here, free is == -1
		suspendCancellable(cont -> {
			final page = deque.push(cont);
			// Unlock
			free.store(0);
			_ -> onWaiterCancelled(page, cont);
		});
	}

	/**
		Called if cancellation wins over the resumption of a waiter. If the waiter is still in the
		deque, it is removed. Otherwise, `release` has already handed the permit to it, so it is
		passed on.
	**/
	function onWaiterCancelled(page, cont:IContinuation<Any>) {
		while (true) {
			final old = free.load();
			if (old < 0) {
				// Someone has the "mutex", let's wait
				BackOff.backOff();
				continue;
			}
			if (old > 0) {
				// The deque is empty while permits are free, so the waiter was handed a permit.
				release();
				return;
			}
			if (free.compareExchange(0, -1) == 0) {
				break;
			}
			BackOff.backOff();
		}
		// If we get here, free == -1.
		if (deque.remove(page, cont)) {
			free.store(0);
		} else {
			handOff();
		}
	}

	/**
		Must be called with free == -1. Hands a permit to the first waiter, or makes it
		available if there are none.
	**/
	function handOff() {
		if (deque.isEmpty()) {
			// Empty deque also means there's room for 1.
			free.store(1);
			return;
		}
		@:nullSafety(Off) final cont:IContinuation<Any> = deque.pop();
		// There's a continuation to execute, so free is 0 again.
		free.store(0);
		// Resume directly instead of dispatching, so that the hand-off is decided right away. If
		// cancellation wins over it, the waiter's cancellation callback passes the permit on.
		// The waiter's coroutine is still dispatched.
		cont.resume(null, null);
	}

	/**
		If a permit is available, acquires it and returns `true`. Otherwise, returns `false`
		without suspending.
	**/
	public function tryAcquire() {
		while (true) {
			var free = free.load();
			if (free <= 0) {
				return false;
			}
			if (this.free.compareExchange(free, free - 1) == free) {
				return true;
			}
		}
	}

	/**
		Releases a permit. If coroutines are waiting in `acquire`, the permit is handed
		to the first one, which is then resumed.

		Throws a `SemaphoreFullException` if the number of available permits is already
		at its maximum.
	**/
	public function release() {
		var old = free.load();
		while (true) {
			if (maxFree == old) {
				throw new SemaphoreFullException();
			}
			if (old < 0) {
				// Someone has the "mutex", let's wait
				BackOff.backOff();
				old = free.load();
				continue;
			}
			if (old == 0) {
				// This is the case where we might have to inspect the deque, so we go to -1.
				final next = free.compareExchange(old, -1);
				if (next == old) {
					// We successfully locked the mutex, leave this loop.
					break;
				} else {
					old = next;
					BackOff.backOff();
					continue;
				}
			}
			final next = free.compareExchange(old, old + 1);
			if (next == old) {
				// Normal release and nobody waits in the deque, we're done.
				return;
			} else {
				// Update failure means waiting.
				old = next;
				BackOff.backOff();
			}
		}
		// If we get here, free == -1.
		handOff();
	}
}
