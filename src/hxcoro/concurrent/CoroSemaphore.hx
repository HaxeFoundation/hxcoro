package hxcoro.concurrent;

import hxcoro.concurrent.exceptions.SemaphoreFullException;
import haxe.coro.Mutex;
import haxe.exceptions.ArgumentException;
import hxcoro.task.CoroTask;
import hxcoro.ds.PagedDeque;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;

class CoroSemaphore {
	final maxFree:Int;
	final dequeMutex:Mutex;
	var deque:Null<PagedDeque<IContinuation<Any>>>;
	var free:AtomicInt;

	public function new(free:Int) {
		if (free < 1) {
			throw new ArgumentException("free", "Maximum free count must be greater than 1");
		}

		maxFree = free;
		dequeMutex = new Mutex();
		this.free = new AtomicInt(free);
	}

	@:coroutine public function acquire() {
		// CAS loop until we update the free atomic or it reports full.
		while (true) {
			final old = free.load();
			if (0 == old) {
				break;
			}

			if (free.compareExchange(old, old - 1) == old) {
				return;
			}
		}
		suspendCancellable(cont -> {
			dequeMutex.acquire();
			if (deque == null) {
				deque = new PagedDeque();
			}
			deque.push(cont);
			dequeMutex.release();
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
		// CAS loop until we update the free atomic or it reports full.
		while (true) {
			final old = free.load();
			if (maxFree == old) {
				throw new SemaphoreFullException();
			}

			if (free.compareExchange(old, old + 1) == old) {
				break;
			}
		}

		dequeMutex.acquire();
		if (deque == null) {
			dequeMutex.release();
			return;
		}
		while (true) {
			if (deque.isEmpty()) {
				// nobody else wants it right now, return
				dequeMutex.release();
				return;
			}
			// a continuation waits for this mutex, wake it up now
			final cont = deque.pop();
			final ct = cont.context.get(CancellationToken);
			if (ct.isCancellationRequested()) {
				// ignore, back to the loop
			} else {
				// continue normally
				while (true) {
					// we need to CAS-decrement the free value here as if we acquired it normally
					final old = free.load();
					if (free.compareExchange(old, old - 1) == old) {
						break;
					}
				}
				dequeMutex.release();
				cont.callAsync();
				return;
			}
		}
	}
}
