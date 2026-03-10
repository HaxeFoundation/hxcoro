/**
 * Benchmark runner that measures the performance of a function.
 *
 * `fn` is called once as a warmup to allow JIT compilation and caching to
 * stabilise, then called once more for the timed measurement.  `fn` must
 * perform exactly `iterations` units of work per call so that the returned
 * `opsPerSec` value is meaningful.
 */
class BenchRunner {
	static public function measure(name:String, iterations:Int, fn:() -> Void):BenchResult {
		fn(); // warmup
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
