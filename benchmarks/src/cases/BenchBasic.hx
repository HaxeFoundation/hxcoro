package cases;

/**
 * Benchmarks for basic coroutine primitives.
 *
 * - basic/yield  – N yield() calls (delay 0) in a single coroutine, measuring
 *                  raw event-loop / scheduler throughput.
 * - basic/spawn  – N trivial concurrent child tasks, measuring task creation
 *                  and dispatch overhead.
 */
class BenchBasic {
	static public function run():Array<BenchResult> {
		return [benchYield(), benchSpawn()];
	}

	static function benchYield():BenchResult {
		final n = BenchConfig.LARGE;
		return BenchRunner.measure("basic/yield", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				yield();
		}));
	}

	static function benchSpawn():BenchResult {
		final n = BenchConfig.SMALL;
		return BenchRunner.measure("basic/spawn", n, () -> CoroRun.run(node -> {
			for (_ in 0...n)
				node.async(_ -> {});
		}));
	}
}
