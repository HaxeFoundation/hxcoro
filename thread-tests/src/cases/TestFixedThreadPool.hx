package cases;

import haxe.atomic.AtomicInt;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.thread.FixedThreadPool;
import hxcoro.thread.ThreadPoolException;
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

// Dispatches itself again from the pool thread until it has run `remaining` times.
private class Redispatch implements IDispatchObject {
	final pool:FixedThreadPool;
	final counter:AtomicInt;
	final started:Lock;
	var remaining:Int;
	public var error:Null<haxe.Exception>;

	public function new(pool:FixedThreadPool, counter:AtomicInt, started:Lock, remaining:Int) {
		this.pool = pool;
		this.counter = counter;
		this.started = started;
		this.remaining = remaining;
	}

	public function onDispatch() {
		if (counter.add(1) == 0) {
			started.release();
		}
		if (--remaining > 0) {
			try {
				pool.run(this);
			} catch (e:haxe.Exception) {
				error = e;
			}
		}
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

	/**
		While `shutDown(true)` ran, `run` from other threads was still accepted after the workers had
		exited, so the work was lost without an exception. Work from outside the pool is now
		rejected once the shutdown has started.
	**/
	function testWorkAcceptedDuringShutdownRuns() {
		final rounds = 50;
		for (round in 0...rounds) {
			final pool = new FixedThreadPool(4);
			final accepted = new AtomicInt(0);
			final executed = new AtomicInt(0);
			final started = new Lock();
			final stopped = new Lock();
			Thread.create(() -> {
				started.release();
				while (true) {
					try {
						pool.run(new Increment(executed));
					} catch (_:ThreadPoolException) {
						break;
					}
					accepted.add(1);
				}
				stopped.release();
			});
			started.wait();
			pool.shutDown(true);
			Assert.isTrue(stopped.wait(10.0), "the producer was never rejected");
			final deadline = Sys.time() + 1.0;
			while (executed.load() < accepted.load() && Sys.time() < deadline) {
				Sys.sleep(0.01);
			}
			if (executed.load() != accepted.load()) {
				Assert.fail('round $round: ${accepted.load() - executed.load()} of ${accepted.load()} accepted dispatches never ran');
				return;
			}
		}
		Assert.pass();
	}

	/**
		`shutDown(false)` marked the pool as shut down right away, while the workers were still
		draining, so a dispatch from a pool thread was rejected and its work lost.
	**/
	function testPoolThreadsDispatchDuringShutdown() {
		final count = 1000;
		final pool = new FixedThreadPool(2);
		final counter = new AtomicInt(0);
		final started = new Lock();
		final obj = new Redispatch(pool, counter, started, count);
		pool.run(obj);
		Assert.isTrue(started.wait(5.0), "the pool never ran the first dispatch");
		pool.shutDown(false);
		final deadline = Sys.time() + 10.0;
		while (counter.load() < count && obj.error == null && Sys.time() < deadline) {
			Sys.sleep(0.01);
		}
		Assert.isNull(obj.error, "a dispatch from a pool thread was rejected during shutdown");
		Assert.equals(count, counter.load());
	}

	function testRejectsWorkAfterShutdown() {
		final pool = new FixedThreadPool(2);
		pool.shutDown(true);
		Assert.raises(() -> pool.run(new Increment(new AtomicInt(0))), ThreadPoolException);
	}
}
