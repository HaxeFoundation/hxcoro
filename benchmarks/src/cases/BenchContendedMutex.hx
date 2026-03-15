package cases;

import hxcoro.concurrent.CoroMutex;

/**
 * Contended-mutex benchmark.
 *
 * WORKERS coroutines simultaneously compete for a single CoroMutex to
 * increment a shared counter.  Each worker calls yield() while holding the
 * mutex, which hands control to the scheduler and gives every other waiting
 * coroutine a genuine opportunity to attempt an acquire.  The result is that
 * every acquire after the first involves a full coroutine suspend/resume
 * cycle through the deque-based waiter queue.
 *
 * The benchmark reports the total number of mutex operations (MESSAGES)
 * performed across all workers.  Because each acquire may require a full
 * coroutine suspend/resume cycle to wait for the previous holder to release,
 * this is substantially slower than the uncontested path.
 *
 * This scenario exercises:
 *   - CoroSemaphore CAS loop under genuine multi-waiter contention
 *   - the deque-based waiter queue (push on contention, pop on release)
 *   - coroutine suspend/resume triggered by lock contention
 *   - fair hand-off between WORKERS competing coroutines
 */
class BenchContendedMutex {
	static public function run():Array<BenchResult> {
		return [benchContendedIncrement()];
	}

	static function benchContendedIncrement():BenchResult {
		final n         = BenchConfig.MESSAGES;
		final workers   = BenchConfig.WORKERS;
		final perWorker = Std.int(n / workers);
		return BenchRunner.measure("contended_mutex/increment", n, () -> {
			CoroRun.run(node -> {
				final mutex   = new CoroMutex();
				var   counter = 0;
				for (_ in 0...workers)
					node.async(_ -> {
						for (_ in 0...perWorker) {
							mutex.acquire();
							// yield() hands control to the scheduler while the
							// mutex is still held, ensuring that other workers
							// are given a chance to attempt an acquire and
							// genuinely suspend on the contended path.
							yield();
							counter++;
							mutex.release();
						}
					});
				// The scope strategy waits for all workers to finish.
			});
		});
	}
}
