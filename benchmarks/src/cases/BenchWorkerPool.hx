package cases;

import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;

/**
 * Worker-pool benchmark.
 *
 * A pool of WORKERS coroutines concurrently drains a bounded channel that is
 * fed by a single coordinator coroutine.  The coordinator writes MESSAGES
 * integers and then closes the channel; workers exit once waitForRead()
 * returns false (channel closed and empty).  The enclosing scope waits for
 * all workers to finish before CoroRun.run returns.
 *
 * The bounded channel capacity (4 × WORKERS) keeps the coordinator and
 * workers tightly coupled so back-pressure is exercised continuously, while
 * still leaving enough headroom to avoid the coordinator suspending on every
 * single write.
 *
 * This scenario exercises:
 *   - sustained bounded-channel read/write throughput under load
 *   - multiple concurrent coroutines sharing a single work queue
 *   - channel back-pressure: coordinator suspends when the channel is full
 *   - cooperative scheduling between producer and consumers
 */
class BenchWorkerPool {
	static public function run():Array<BenchResult> {
		return [benchDrainChannel()];
	}

	static function benchDrainChannel():BenchResult {
		final n       = BenchConfig.MESSAGES;
		final workers = BenchConfig.WORKERS;
		return BenchRunner.measure("worker_pool/drain_channel", n, () -> {
			final ch = Channel.createBounded({size: workers * 4});
			CoroRun.run(node -> {
				// Spawn the worker pool.  Each worker gets its own Out to
				// avoid cross-thread aliasing on threaded targets.
				for (_ in 0...workers)
					node.async(_ -> {
						final out = new Out();
						while (ch.waitForRead())
							while (ch.tryRead(out)) {}
					});
				// Feed all messages then signal end-of-stream.
				for (i in 0...n)
					ch.write(i);
				ch.close();
			});
		});
	}
}
