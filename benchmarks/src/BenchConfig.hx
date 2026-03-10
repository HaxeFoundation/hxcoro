/**
 * Target-dependent scenario parameters.
 *
 * Sized so that each benchmark runs for roughly 3 – 8 seconds total on its
 * target tier, which keeps GC and JIT jitter from dominating the result.
 *
 * WORKERS        – number of concurrent coroutine workers / child tasks
 * MESSAGES       – total items fed through channel or mutex benchmarks
 * ROUNDS         – number of repeated rounds for fan-out / cancellation
 * GENERATOR_ITERS – iterations for the generator benchmark (no event-loop
 *                   cost per iteration, so it needs more to fill the window)
 */
class BenchConfig {
	#if (cpp || jvm)
	// CPP and JVM use a multi-threaded dispatcher, giving them the highest
	// channel throughput.  Kept in one tier because their overall suite times
	// are similar (~5–8 s).
	public static final WORKERS         = 8;
	public static final MESSAGES        = 150_000;
	public static final ROUNDS          = 15_000;
	public static final GENERATOR_ITERS = 500_000;
	#elseif hl
	// HashLink uses a multi-threaded dispatcher but its channel operations are
	// significantly slower than CPP/JVM in practice, so it gets its own tier.
	public static final WORKERS         = 8;
	public static final MESSAGES        = 25_000;
	public static final ROUNDS          = 3_000;
	public static final GENERATOR_ITERS = 100_000;
	#elseif js
	// Single-threaded TrampolineDispatcher — no async-timer overhead, so
	// channel throughput is very high.  Scaled up to match the suite duration
	// of other targets.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 500_000;
	public static final ROUNDS          = 30_000;
	public static final GENERATOR_ITERS = 1_000_000;
	#elseif python
	// CPython interpreter — slower per coroutine step than JVM/HL but fast
	// enough that the original 1 k/100 config finished in < 200 ms.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 50_000;
	public static final ROUNDS          = 5_000;
	public static final GENERATOR_ITERS = 250_000;
	#elseif php
	// PHP interpreter — similar performance envelope to Python.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 25_000;
	public static final ROUNDS          = 2_500;
	public static final GENERATOR_ITERS = 125_000;
	#else
	// Eval, Neko, Lua, and any other target.
	public static final WORKERS         = 4;
	public static final MESSAGES        = 13_000;
	public static final ROUNDS          = 5_000;
	public static final GENERATOR_ITERS = 80_000;
	#end
}
