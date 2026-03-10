package cases;

import hxcoro.generators.HaxeGenerator;

/**
 * Generator iteration benchmark.
 *
 * Creates a HaxeGenerator that yields N integers, then iterates over all of
 * them.  Generators use their own SelfDispatcher and never need an event loop,
 * so this isolates the coroutine state-machine / suspension overhead from
 * scheduler costs.
 */
class BenchGenerator {
	static public function run():Array<BenchResult> {
		return [benchIterate()];
	}

	static function benchIterate():BenchResult {
		final n = BenchConfig.GENERATOR_ITERS;
		return BenchRunner.measure("generator/iterate", n, () -> {
			final gen = HaxeGenerator.create(yield -> {
				for (i in 0...n)
					yield(i);
			});
			for (_ in gen) {}
		});
	}
}
