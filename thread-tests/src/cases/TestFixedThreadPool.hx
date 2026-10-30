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
		The thread that constructed the pool adds to a queue of its own without locking. All
		other non-pool threads share a queue, which supports only one producer, so they have to
		take the mutex. The constructing thread used to have the shared queue itself installed
		as its own queue, so it added to it without the mutex and raced with the other threads.

		This is a stress test. On eval a single round used to lose dispatches most of the time,
		so the test runs up to five rounds and stops at the first loss.
	**/
	function testSharedQueueAcceptsDispatchesFromForeignThreads() {
		final n = 50000;
		final otherThreads = 2;
		final total = (otherThreads + 1) * n;
		for (round in 0...5) {
			final pool = new FixedThreadPool(4);
			final counter = new AtomicInt(0);
			final otherDone = new Lock();
			for (_ in 0...otherThreads) {
				Thread.create(() -> {
					for (_ in 0...n) {
						pool.run(new Increment(counter));
					}
					otherDone.release();
				});
			}
			for (_ in 0...n) {
				pool.run(new Increment(counter));
			}
			for (_ in 0...otherThreads) {
				otherDone.wait(10.0);
			}
			final deadline = Sys.time() + 2.0;
			while (counter.load() < total && Sys.time() < deadline) {
				Sys.sleep(0.01);
			}
			pool.shutDown(true);
			final executed = counter.load();
			if (executed != total) {
				Assert.fail('round $round: only $executed of $total dispatches were executed');
				return;
			}
		}
		Assert.pass();
	}
}
