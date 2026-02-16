package hxcoro.concurrent;

import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.exceptions.ArgumentException;
import haxe.exceptions.CoroutineException;
import hxcoro.Coro.*;
import hxcoro.concurrent.AtomicInt;
import hxcoro.concurrent.BackOff;
import hxcoro.ds.PagedDeque;

using hxcoro.util.Convenience;

class CoroLatchImpl {
	final counter:AtomicInt;
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
	public function arrive(n:Int) {
		if (n <= 0) {
			throw new ArgumentException("n", "Argument to arrive must be >= 1");
		}
		switch (decreaseCounter(n)) {
			case 0:
			case target:
				counter.store(target);
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
		switch (decreaseCounter(0)) {
			case 0:
			case target:
				suspendCancellable(cont -> {
					deque ??= new PagedDeque();
					deque.push(cont);
					counter.store(target);
					null;
				});
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
				suspendCancellable(cont -> {
					deque ??= new PagedDeque();
					deque.push(cont);
					counter.store(target);
					null;
				});
		}
	}

	/**
		Decreases the counter for the next phase, then acts as `arrive(1)` for the current one.
	**/
	public function arriveAndDrop() {
		while (true) {
			switch (counter.load()) {
				case -1:
					// Locked, let's wait.
				case 0:
					throw new CoroutineException("Invalid call to arriveAndDrop when counter is at 0");
				case old:
					if (counter.compareExchange(old, -1) == old) {
						--maxCounter;
						if (old == 1) {
							complete();
						} else {
							counter.store(old - 1);
						}
						return;
					}
			}
			BackOff.backOff();
		}
	}

	// return > 0 means counter == -1, so caller has to set counter to return value.

	function decreaseCounter(n:Int) {
		while (true) {
			switch (counter.load()) {
				case -1:
					// Locked, let's wait.
				case 0:
					// This should only happen in latch mode and means we're already open.
					return 0;
				case old:
					final target = old - n;
					if (target <= 0) {
						if (counter.compareExchange(old, -1) == old) {
							complete();
							return 0;
						}
					} else if (counter.compareExchange(old, -1) == old) {
						return target;
					}
			}
			BackOff.backOff();
		}
	}

	function complete() {
		final deque = deque;
		this.deque = null;
		var restore = if (barrierCallback != null) {
			// In barrier mode we execute the callback and then set the counter back to maxCounter.
			barrierCallback();
			counter.store(maxCounter);
		} else {
			// In latch mode we just store 0.
			counter.store(0);
		}

		if (deque == null) {
			return;
		}
		while (!deque.isEmpty()) {
			@:nullSafety(Off) final cont:IContinuation<Any> = deque.pop();
			if (cont.context.isCancellationRequested()) {
				continue;
			}
			cont.callAsync();
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