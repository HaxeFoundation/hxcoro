package review;

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

/**
	Known failures from the 1.0 review: `FixedThreadPool` shutdown.
**/
class TestFixedThreadPool extends atest.Test {
	/**
		P6a: `shutDown(true)` can lose work that is added while it runs.

		`src/hxcoro/thread/FixedThreadPool.hx`: `run` (`:78-90`) only rejects work once the state is
		`ShutDown`, so it still accepts work while `ShuttingDown`. The workers exit after two empty
		passes over the queues (worker exit logic around `:218`), so work added after that, e.g. a
		timer dispatch from the scheduler thread, is never run and nothing reports it.

		P6b, not covered here: with `shutDown(false)`, the state is `ShutDown` right away while the
		workers still drain. A worker that re-dispatches gets a `ThreadPoolException`, `threadEntry`
		restarts a thread after shutdown, and the continuation is lost.

		Fix: either reject anything that isn't `Active` (and make callers cope), or have the workers
		drain until the state is `ShutDown` and the queues are empty, and accept `run` during
		`ShuttingDown` only from pool threads. Document the chosen contract on `IThreadPool`. Work
		must either run or be rejected by `run` throwing, never be lost silently.
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
}
