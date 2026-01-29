package hxcoro.concurrent;

import hxcoro.concurrent.exceptions.SemaphoreFullException;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.PagedDeque;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;

class CoroSemaphore {
	final maxFree:Int;
	var deque:Null<PagedDeque<IContinuation<Any>>>;
	var free:AtomicInt;

	public function new(free:Int) {
		if (free < 1) {
			throw new ArgumentException("free", "Maximum free count must be greater than 1");
		}

		maxFree = free;
		this.free = new AtomicInt(free);
	}

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
			deque ??= new PagedDeque();
			deque.push(cont);
			// Unlock
			free.store(0);
		});
	}

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

	public function release() {
		var old = free.load();
		while (true) {
			if (maxFree == old) {
				throw new SemaphoreFullException();
			}
			if (old < 0) {
				// Someone has the "mutex", let's wait
				BackOff.backOff();
				continue;
			}
			if (old == 0) {
				// This is the case where we might have to inspect the deque, so we go to -1.
				if (free.compareExchange(old, -1) == old) {
					// We successfully locked the mutex, leave this loop.
					break;
				} else {
					BackOff.backOff();
					continue;
				}
			}
			if (free.compareExchange(old, old + 1) == old) {
				// Normal release and nobody waits in the deque, we're done.
				return;
			} else {
				// Update failure means waiting.
				BackOff.backOff();
			}
		}
		// If we get here, free == -1.
		if (deque == null) {
			// No deque at all means there's room for 1 now.
			free.store(1);
			return;
		}
		while (true) {
			if (deque.isEmpty()) {
				// Empty deque also means there's room for 1.
				free.store(1);
				return;
			}
			final cont = deque.pop();
			final ct = cont.context.get(CancellationToken);
			if (ct.isCancellationRequested()) {
				// Ignore, back to the loop.
				continue;
			}
			// There's a continuation to execute, so free is 0 again.
			free.store(0);
			cont.callAsync();
			break;
		}
	}
}
