package cases;

import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;

/**
 * Three-stage data-pipeline benchmark.
 *
 * Integers flow through three concurrent pipeline stages connected by a pair
 * of bounded channels:
 *
 *   Source  →  [ch1]  →  Transform  →  [ch2]  →  Sink
 *
 *   Source:    writes MESSAGES integers into ch1.
 *   Transform: reads from ch1, doubles each value, writes to ch2.
 *   Sink:      reads from ch2 and accumulates a running sum.
 *
 * All three stages run as concurrent child tasks of the same scope; the scope
 * blocks until every stage has finished.  The bounded channel capacity (16)
 * provides natural back-pressure between stages.
 *
 * This scenario exercises:
 *   - sustained throughput across two chained bounded channels
 *   - three concurrent coroutines with producer / transformer / consumer roles
 *   - back-pressure propagation along the pipeline
 *   - coordinated shutdown via channel close
 */
class BenchPipeline {
	static public function run():Array<BenchResult> {
		return [benchThreeStage()];
	}

	static function benchThreeStage():BenchResult {
		final n = BenchConfig.MESSAGES;
		return BenchRunner.measure("pipeline/three_stage", n, () -> {
			final ch1 = Channel.createBounded({size: 16});
			final ch2 = Channel.createBounded({size: 16});
			CoroRun.run(node -> {
				// Stage 1 – source
				node.async(_ -> {
					for (i in 0...n)
						ch1.write(i);
					ch1.close();
				});
				// Stage 2 – transform
				node.async(_ -> {
					final out = new Out();
					while (ch1.waitForRead())
						while (ch1.tryRead(out))
							ch2.write(out.get() * 2);
					ch2.close();
				});
				// Stage 3 – sink
				node.async(_ -> {
					var sum = 0;
					final out = new Out();
					while (ch2.waitForRead())
						while (ch2.tryRead(out))
							sum += out.get();
				});
			});
		});
	}
}
