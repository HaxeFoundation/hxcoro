/**
 * Target-dependent iteration counts to keep benchmark runtime reasonable.
 * Fast targets (jvm, cpp) can handle more iterations than slow ones (python, php, neko).
 */
class BenchConfig {
	#if (cpp || jvm)
	public static final SMALL  = 2_000;
	public static final MEDIUM = 10_000;
	public static final LARGE  = 100_000;
	#elseif (python || php || neko)
	public static final SMALL  = 50;
	public static final MEDIUM = 500;
	public static final LARGE  = 2_000;
	#else // hl, js, eval
	public static final SMALL  = 500;
	public static final MEDIUM = 2_000;
	public static final LARGE  = 10_000;
	#end
}
