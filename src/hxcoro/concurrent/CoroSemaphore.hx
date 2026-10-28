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
		Acquires a permit, suspending until one becomes available if necessary. Waiting
		for a permit reacts to cancellation of the calling coroutine.
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
			deque.push(cont);
			// Unlock
			free.store(0);
			null;
		});
	}

	/**
		Acquires a permit if one is available without suspending. Returns `true` if a
		permit was acquired, `false` otherwise.
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
		while (true) {
			if (deque.isEmpty()) {
				// Empty deque also means there's room for 1.
				free.store(1);
				return;
			}
			@:nullSafety(Off) final cont:IContinuation<Any> = deque.pop();
			if (cont.context.isCancellationRequested()) {
				continue;
			}
			// There's a continuation to execute, so free is 0 again.
			free.store(0);
			cont.callAsync();
			break;
		}
	}
}
