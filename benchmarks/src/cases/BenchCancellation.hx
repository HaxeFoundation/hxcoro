package cases;

/**
 * Task-cancellation benchmark.
 *
 * Simulates repeated "cancel a batch of stalled workers" waves.  Each round:
 *
 *   1. A supervisor scope spawns WORKERS child tasks that each wait for a
 *      very long delay (60 seconds) – they would never complete naturally.
 *   2. The supervisor calls cancelChildren() immediately after spawning.
 *   3. The supervisor waits for all children to finish (they complete as
 *      cancelled once their timer handles are closed and their continuations
 *      are resumed with CancellationException).
 *
 * The measured unit is the total number of cancelled tasks (ROUNDS × WORKERS).
 *
 * This scenario exercises:
 *   - CancellingContinuation cleanup callback (timer-handle close on delay)
 *   - cancellation propagation from parent node to child tasks
 *   - CoroSupervisorStrategy waiting for cancelled (but not failing) children
 *   - the full coroutine teardown path for suspended tasks
 */
class BenchCancellation {
	static public function run():Array<BenchResult> {
		return [benchCancelWaves()];
	}

	static function benchCancelWaves():BenchResult {
		final workers = BenchConfig.WORKERS;
		// Each cancellation round drives an event-loop drain cycle to close
		// timer handles, which adds overhead beyond ordinary task teardown.
		// Dividing ROUNDS keeps total wall-clock time on par with other cases.
		final CANCEL_DIVISOR = 3;
		final rounds  = Std.int(BenchConfig.ROUNDS / CANCEL_DIVISOR);
		return BenchRunner.measure("cancellation/waves", rounds * workers, () -> {
			CoroRun.run(node -> {
				for (_ in 0...rounds) {
					supervisor(inner -> {
						for (_ in 0...workers)
							inner.async(_ -> delay(60_000));
						inner.cancelChildren();
						// Returning from the lambda lets the supervisor wait
						// for all cancelled children to reach a terminal state.
					});
				}
			});
		});
	}
}
