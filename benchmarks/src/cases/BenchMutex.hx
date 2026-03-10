package cases;

import hxcoro.concurrent.CoroMutex;

/**
 * Uncontested mutex benchmark.
 *
 * A single coroutine acquires and immediately releases the mutex N times.
 * Because there is no contention the semaphore CAS never suspends, so this
 * measures the raw overhead of CoroMutex's lock/unlock path.
 */
class BenchMutex {
	static public function run():Array<BenchResult> {
		return [benchLock()];
	}

	static function benchLock():BenchResult {
		final n = BenchConfig.LARGE;
		return BenchRunner.measure("mutex/lock", n, () -> CoroRun.run(node -> {
			final m = new CoroMutex();
			for (_ in 0...n) {
				m.acquire();
				m.release();
			}
		}));
	}
}
