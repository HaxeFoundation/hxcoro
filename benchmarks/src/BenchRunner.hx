/**
 * Benchmark runner that measures the performance of a function.
 *
 * `fn` is called several times as a warmup to let JIT compilation, caches,
 * and GC reach a steady state, then called once for the timed measurement.
 * `fn` must perform exactly `iterations` units of work per call so that the
 * returned `opsPerSec` value is meaningful.
 *
 * JVM gets extra warmup rounds because its JIT needs more iterations to fully
 * compile all hot coroutine paths before producing stable numbers.
 */
class BenchRunner {
	static public function measure(name:String, iterations:Int, fn:() -> Void):BenchResult {
		final warmupRounds = #if jvm 5 #else 1 #end;
		for (_ in 0...warmupRounds) fn();
		final start = haxe.Timer.stamp();
		fn();
		final elapsed = haxe.Timer.stamp() - start;
		return {
			name:       name,
			opsPerSec:  iterations / elapsed,
			iterations: iterations,
			elapsedMs:  elapsed * 1000,
		};
	}
}
