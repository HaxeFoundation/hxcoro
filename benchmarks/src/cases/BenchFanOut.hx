package cases;

/**
 * Fan-out / gather benchmark.
 *
 * Each of ROUNDS rounds:
 *   1. WORKERS child tasks are spawned concurrently.  Each does a small
 *      amount of work (a tight loop) then yields once to ensure a genuine
 *      async suspend/resume cycle before returning its result.
 *   2. The parent awaits every child in sequence and sums the results.
 *
 * The yield() inside each worker means results are not ready before the
 * parent starts awaiting, so the full await-suspension path is exercised
 * alongside the already-completed fast path for later tasks in the batch.
 *
 * The measured unit is the total number of task completions (ROUNDS × WORKERS).
 *
 * This scenario exercises:
 *   - concurrent child-task creation and dispatch overhead
 *   - the await-suspension path (task not yet complete when first awaited)
 *   - the already-completed fast path (later tasks done by the time we await)
 *   - result propagation through ICoroTask.await()
 *   - scope-level child tracking across multiple concurrent batches
 */
class BenchFanOut {
	static public function run():Array<BenchResult> {
		return [benchGather()];
	}

	static function benchGather():BenchResult {
		final workers = BenchConfig.WORKERS;
		// Divide ROUNDS by WORKERS so the total task-completion count
		// (rounds × workers) is at least ROUNDS.  Math.ceil ensures we never
		// run fewer total completions than the configured target even if
		// ROUNDS is not exactly divisible by WORKERS.
		final rounds  = Math.ceil(BenchConfig.ROUNDS / workers);
		return BenchRunner.measure("fan_out/gather", rounds * workers, () -> {
			CoroRun.run(node -> {
				for (_ in 0...rounds) {
					// Launch all workers concurrently.
					final tasks = [for (_ in 0...workers)
						node.async(_ -> {
							// One yield so the task is genuinely async.
							yield();
							var s = 0;
							for (j in 0...50) s += j;
							return s;
						})
					];
					// Gather results sequentially.
					var total = 0;
					for (t in tasks) total += t.await();
				}
			});
		});
	}
}
