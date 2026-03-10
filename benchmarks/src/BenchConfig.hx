/**
 * Target-dependent scenario parameters.
 *
 * Sized so that each benchmark runs for roughly 0.5 – 2 seconds on its
 * target tier, which keeps GC and JIT jitter from dominating the result.
 *
 * WORKERS        – number of concurrent coroutine workers / child tasks
 * MESSAGES       – total items fed through channel or mutex benchmarks
 * ROUNDS         – number of repeated rounds for fan-out / cancellation
 * GENERATOR_ITERS – iterations for the generator benchmark (no event-loop
 *                   cost per iteration, so it needs more to fill the window)
 */
class BenchConfig {
	#if (cpp || jvm || hl)
	// cpp, jvm, and hl all use a multi-threaded dispatcher by default, which
	// gives them substantially higher throughput for channel and task work than
	// event-loop targets.  They are grouped together here based on observed
	// performance characteristics rather than strict thread-topology guarantees.
	public static final WORKERS         = 8;
	public static final MESSAGES        = 150_000;
	public static final ROUNDS          = 15_000;
	public static final GENERATOR_ITERS = 500_000;
	#elseif js
	// Single-threaded, but TrampolineDispatcher skips async-timer overhead,
	// making simple channel operations far faster than event-loop targets.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 200_000;
	public static final ROUNDS          = 10_000;
	public static final GENERATOR_ITERS = 300_000;
	#elseif (python || php)
	// Slow interpreter targets.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 1_000;
	public static final ROUNDS          = 100;
	public static final GENERATOR_ITERS = 5_000;
	#else
	// eval, neko, and any other target.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 8_000;
	public static final ROUNDS          = 3_000;
	public static final GENERATOR_ITERS = 50_000;
	#end
}
