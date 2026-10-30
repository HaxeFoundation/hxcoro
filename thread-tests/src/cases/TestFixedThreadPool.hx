package cases;

import haxe.atomic.AtomicInt;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.thread.FixedThreadPool;
import sys.thread.Lock;
import sys.thread.Thread;

private class Increment implements IDispatchObject {
	final counter:AtomicInt;

	public function new(counter:AtomicInt) {
		this.counter = counter;
	}

	public function onDispatch() {
		counter.add(1);
	}
}

class TestFixedThreadPool extends atest.Test {
	/**
		Threads outside the pool share the main queue, which supports only one producer. This
		includes the thread that constructed the pool: it used to have the main queue installed
		as its own queue, so it added to it without the mutex and raced with other threads.

		This is a stress test. On eval a single round used to lose dispatches most of the time,
		so the test runs up to five rounds and stops at the first loss.
	**/
	function testMainQueueAcceptsDispatchesFromTwoForeignThreads() {
		final n = 50000;
		for (round in 0...5) {
			final pool = new FixedThreadPool(4);
			final counter = new AtomicInt(0);
			final otherDone = new Lock();
			Thread.create(() -> {
				for (_ in 0...n) {
					pool.run(new Increment(counter));
				}
				otherDone.release();
			});
			for (_ in 0...n) {
				pool.run(new Increment(counter));
			}
			otherDone.wait(10.0);
			final deadline = Sys.time() + 2.0;
			while (counter.load() < 2 * n && Sys.time() < deadline) {
				Sys.sleep(0.01);
			}
			pool.shutDown(true);
			final executed = counter.load();
			if (executed != 2 * n) {
				Assert.fail('round $round: only $executed of ${2 * n} dispatches were executed');
				return;
			}
		}
		Assert.pass();
	}
}
