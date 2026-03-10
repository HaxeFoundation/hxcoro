package cases;

import hxcoro.Coro.*;
import hxcoro.concurrent.CoroLatch;

/**
 * Benchmarks covering the full task architecture: spawning, awaiting,
 * lazy tasks, structured scopes, supervisors, timeouts, and nested spawning.
 *
 * Together these cases exercise every major code path in CoroTask,
 * CoroBaseTask, and the scope / supervisor / timeout continuations, so a
 * regression in any one of them should show up clearly in the numbers.
 */
class BenchTask {
	static public function run():Array<BenchResult> {
		return [
			benchSequentialAwait(),
			benchConcurrentLatch(),
			benchLazyAwait(),
			benchScope(),
			benchSupervisor(),
			benchTimeoutNoExpire(),
			benchNested(),
		];
	}

	/**
	 * Spawn a trivial child task and immediately await its result, N times
	 * in sequence.  Each iteration exercises the full suspend-dispatch-
	 * complete-resume path of a single task.
	 */
	static function benchSequentialAwait():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("task/sequential_await", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				node.async(_ -> {}).await();
		}));
	}

	/**
	 * Spawn N tasks concurrently; each one calls latch.arrive(1); the
	 * parent then waits on the latch.  Measures the throughput of
	 * concurrent task dispatch plus CoroLatch synchronisation.
	 */
	static function benchConcurrentLatch():BenchResult {
		final n = BenchConfig.SMALL;
		return BenchRunner.measure("task/concurrent_latch", n, () -> CoroRun.run(node -> {
			final latch = new CoroLatch(n);
			for (_ in 0...n)
				node.async(_ -> latch.arrive(1));
			latch.wait();
		}));
	}

	/**
	 * Create a lazy (not-yet-started) task and await it, N times in
	 * sequence.  Awaiting a lazy task starts it; this path differs from
	 * node.async() so it is worth measuring separately.
	 */
	static function benchLazyAwait():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("task/lazy_await", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				node.lazy(_ -> {}).await();
		}));
	}

	/**
	 * Call scope() N times in sequence with an empty body.  Each call
	 * creates a CoroScopeStrategy task, runs it, and tears it down.
	 */
	static function benchScope():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("task/scope", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				scope(inner -> {});
		}));
	}

	/**
	 * Call supervisor() N times in sequence with an empty body.
	 * Tests the CoroSupervisorStrategy task creation and teardown path.
	 */
	static function benchSupervisor():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("task/supervisor", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				supervisor(inner -> {});
		}));
	}

	/**
	 * Call timeout() N times where the lambda always completes well within
	 * the timeout window.  Measures the cost of scheduling and immediately
	 * cancelling a timer handle without ever triggering the timeout path.
	 */
	static function benchTimeoutNoExpire():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("task/timeout_no_expire", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				timeout(1000, inner -> {});
		}));
	}

	/**
	 * Spawn N outer tasks; each outer task spawns one inner task (2-level
	 * nesting).  The scope strategy on CoroRun.run guarantees that all outer
	 * tasks (and therefore all their inner children) finish before run()
	 * returns, so the full 2N-task tree is always measured.
	 */
	static function benchNested():BenchResult {
		final n = BenchConfig.SMALL;
		return BenchRunner.measure("task/nested", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				node.async(inner -> {
					inner.async(_ -> {});
				});
		}));
	}
}
