package cases;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
 * Scheduler benchmarks.
 *
 * - `scheduler/yield_burst` runs many coroutines that only `yield()`, through
 *   `CoroRun.run`. Most of their events are due in the same millisecond, which
 *   is the case the heap's handling of equal due times matters for.
 * - `scheduler/heap_same_time` and `scheduler/heap_mixed` schedule plain events
 *   on a `VirtualTimeScheduler` and dispatch them, which measures the heap on
 *   its own. The first uses one due time for all events, the second spreads
 *   them over 1000 due times.
 */
class BenchScheduler {
	static public function run():Array<BenchResult> {
		return [benchYieldBurst(), benchHeap("scheduler/heap_same_time", _ -> 10), benchHeap("scheduler/heap_mixed", i -> ((i % 1000) * 7919) % 1000)];
	}

	static function benchYieldBurst():BenchResult {
		final tasks = BenchConfig.WORKERS * 4;
		final yieldsPerTask = Math.ceil(BenchConfig.ROUNDS * 4 / tasks);
		return BenchRunner.measure("scheduler/yield_burst", tasks * yieldsPerTask, () -> {
			CoroRun.run(node -> {
				for (_ in 0...tasks) {
					node.async(_ -> {
						for (_ in 0...yieldsPerTask) {
							yield();
						}
					});
				}
			});
		});
	}

	static function benchHeap(name:String, dueTime:Int -> Int):BenchResult {
		final events = BenchConfig.MESSAGES * 4;
		return BenchRunner.measure(name, events, () -> {
			final scheduler = new VirtualTimeScheduler();
			var dispatched = 0;
			final cont = new FunctionContinuation(Context.empty, (_, _) -> dispatched++);
			for (i in 0...events) {
				scheduler.schedule(dueTime(i), cont);
			}
			scheduler.advanceBy(1000);
			if (dispatched != events) {
				throw 'dispatched $dispatched of $events events';
			}
		});
	}
}
