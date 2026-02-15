package hxcoro.concurrent;

import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.exceptions.ArgumentException;
import hxcoro.Coro.*;
import hxcoro.concurrent.AtomicInt;
import hxcoro.concurrent.BackOff;
import hxcoro.ds.PagedDeque;

using hxcoro.util.Convenience;

/**
	A latch allows coroutines to wait until its counter reaches zero.
**/
class CoroLatch {
	final counter:AtomicInt;
	var deque:Null<PagedDeque<IContinuation<Any>>>;

	/**
		Creates a new `CoroLatch` instance with an initial `counter` value.
	**/
	public function new(counter:Int) {
		if (counter < 0) {
			throw new ArgumentException("counter", "counter must be >= 0");
		}
		this.counter = new AtomicInt(counter);
	}

	/**
		Decreases the internal counter value by `n`. If this changes its value to 0,
		all waiting continuations are resumed.

		Throws an `ArgumentException` if `n <= 0`.

		The `counter - n` subtraction is clamped to 0 if it were to result in a
		negative value. By extension, this means that this call has no effect if the
		counter is 0 already.
	**/
	public function countDown(n:Int) {
		if (n <= 0) {
			throw new ArgumentException("n", "Argument to countDown must be >= 1");
		}
		while (true) {
			switch (counter.load()) {
				case -1:
					// Someone modifies the deque, wait
				case 0:
					// Already open, ignore
					return;
				case old:
					if (old - n <= 0) {
						// Potential open
						if (counter.compareExchange(old, 0) == old) {
							// Acquire worked, flush all waiters
							final deque = deque;
							if (deque == null) {
								return;
							}
							this.deque = null;
							while (!deque.isEmpty()) {
								@:nullSafety(Off) final cont:IContinuation<Any> = deque.pop();
								final ct = cont.context.get(CancellationToken);
								if (ct != null && ct.isCancellationRequested()) {
									// Ignore, back to the loop.
									continue;
								}
								cont.callAsync();
							}
							return;
						}
					} else if (counter.compareExchange(old, old - 1) == old) {
						// Successful decrease to something > 0
						return;
					}
			}
			BackOff.backOff();
			continue;
		}
	}

	/**
		Returns true if the internal counter is 0.
	**/
	public function tryWait() {
		return counter.load() == 0;
	}

	/**
		Waits for the internal counter to reach 0. If it is 0 already, this call resumes
		immediately. Otherwise the continuation is registered to be resumed once the
		value becomes 0.
	**/
	@:coroutine public function wait() {
		while (true) {
			switch (counter.load()) {
				case -1:
					// Locked, let's wait
				case 0:
					// Already 0, return
					return;
				case old:
					if (counter.compareExchange(old, -1) == old) {
						// Successful lock
						suspendCancellable(cont -> {
							deque ??= new PagedDeque();
							deque.push(cont);
							counter.store(old);
							null;
						});
						return;
					}
					// Locking failed, let's wait
			}
			BackOff.backOff();
		}
	}

	/**
		Decreases the internal counter value by `n` and waits for it to reach 0.

		This is equivalent to calling `countDown(n)` followed by `wait()`.
	**/
	@:coroutine public function arriveAndWait(n:Int) {
		countDown(n);
		wait();
	}
}