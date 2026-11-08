package hxcoro.concurrent;

import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.exceptions.ArgumentException;
import haxe.exceptions.CancellationException;
import haxe.exceptions.CoroutineException;
import hxcoro.Coro.*;
import hxcoro.ds.PagedDeque;

using hxcoro.util.Convenience;

/**
	The shared implementation of `CoroLatch` and `CoroBarrier`.
**/
class CoroLatchImpl {
	final counter:LockableAtomic<Int>;
	final barrierCallback:Null<() -> Void>;
	var maxCounter:Int;
	var deque:Null<PagedDeque<IContinuation<Any>>>;

	/**
		Creates a new `CoroLatch` instance with an initial `counter` value.
	**/
	public function new(counter:Int, barrierCallback:Null<() -> Void>) {
		if (counter < 0) {
			throw new ArgumentException("counter", "counter must be >= 0");
		}
		this.barrierCallback = barrierCallback;
		this.maxCounter = counter;
		this.counter = new LockableAtomic(counter);
	}

	/**
		Decreases the internal counter value by `n`. If this changes its value to 0,
		all waiting continuations are resumed.

		Throws an `ArgumentException` if `n <= 0`.

		The `counter - n` subtraction is clamped to 0 if it were to result in a
		negative value. By extension, this means that this call has no effect if the
		counter is 0 already.
	**/
	public function arrive(n:Int) {
		if (n <= 0) {
			throw new ArgumentException("n", "Argument to arrive must be >= 1");
		}
		switch (decreaseCounter(n)) {
			case 0:
			case target:
				counter.unlock(target);
		}
	}

	/**
		Returns `true` if the counter has reached 0, without suspending.
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
		switch (decreaseCounter(0)) {
			case 0:
			case target:
				suspendCancellable(cont -> addWaiter(cont, target));
		}
	}

	/**
		Decreases the internal counter value by `n` and waits for it to reach 0.

		This is equivalent to calling `arrive(n)` followed by `wait()`.

		See `arrive` for details about the arrival process.
	**/
	@:coroutine public function arriveAndWait(n:Int) {
		if (n <= 0) {
			throw new ArgumentException("n", "Argument to arriveAndWait must be >= 1");
		}
		switch (decreaseCounter(n)) {
			case 0:
			case target:
				suspendCancellable(cont -> addWaiter(cont, target));
		}
	}

	/**
		Must be called with the counter locked. Adds `cont` to the waiters, unlocks the counter with
		`target` and returns the cancellation callback that removes `cont` again.
	**/
	function addWaiter(cont:IContinuation<Any>, target:Int) {
		var deque = this.deque;
		if (deque == null) {
			deque = new PagedDeque();
			this.deque = deque;
		}
		final page = deque.push(cont);
		counter.unlock(target);
		return (_:CancellationException) -> removeWaiter(deque, page, cont);
	}

	/**
		Removes a cancelled waiter, so that it isn't kept alive until the counter reaches 0.
	**/
	function removeWaiter(deque:PagedDeque<IContinuation<Any>>, page, cont:IContinuation<Any>) {
		switch (counter.lockUnless(0)) {
			case 0:
				// The latch is open, so its waiters are being resumed already.
			case old:
				// If the deque was replaced, the phase completed and `complete` is resuming
				// the waiters of the old deque, which we must not modify.
				if (this.deque == deque) {
					deque.remove(page, cont);
				}
				counter.unlock(old);
		}
	}

	/**
		Decreases the counter for the next phase, then acts as `arrive(1)` for the current one.
	**/
	public function arriveAndDrop() {
		switch (counter.lockUnless(0)) {
			case 0:
				throw new CoroutineException("Invalid call to arriveAndDrop when counter is at 0");
			case old:
				--maxCounter;
				if (old == 1) {
					complete();
				} else {
					counter.unlock(old - 1);
				}
		}
	}

	// A result > 0 means that the counter is locked, and the caller has to unlock it with that value.
	function decreaseCounter(n:Int) {
		switch (counter.lockUnless(0)) {
			case 0:
				// This should only happen in latch mode and means we're already open.
				return 0;
			case old:
				final target = old - n;
				if (target <= 0) {
					complete();
					return 0;
				}
				return target;
		}
	}

	function complete() {
		final deque = deque;
		this.deque = null;
		// Unlock before running the callback, so that it may use the barrier for the next phase and
		// other threads don't spin while it runs. The waiters of this phase were taken out above, so
		// they are still resumed after the callback. A latch stays open at 0.
		final barrierCallback = barrierCallback;
		counter.unlock(barrierCallback != null ? maxCounter : 0);
		var callbackError:Null<haxe.Exception> = null;
		if (barrierCallback != null) {
			// If the callback throws, the waiters are still resumed and the exception is rethrown afterwards.
			try {
				barrierCallback();
			} catch (e:haxe.Exception) {
				callbackError = e;
			}
		}

		if (deque != null) {
			while (!deque.isEmpty()) {
				@:nullSafety(Off) final cont:IContinuation<Any> = deque.pop();
				if (cont.context.isCancellationRequested()) {
					continue;
				}
				cont.callAsync();
			}
		}
		if (callbackError != null) {
			throw callbackError;
		}
	}
}

/**
	A latch allows coroutines to wait until its counter reaches zero.
**/
@:forward("arrive", "tryWait", "wait", "arriveAndWait")
abstract CoroLatch(CoroLatchImpl) {
	/**
		Creates a new `CoroLatch` instance with the specified `counter` value.
	**/
	public inline function new(counter:Int) {
		this = new CoroLatchImpl(counter, null);
	}
}