package cases;

import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;

/**
 * Channel ping-pong benchmark.
 *
 * A writer task sends N integers through a bounded channel of capacity 1; a
 * reader coroutine drains them.  With capacity 1 the two sides alternate –
 * every write suspends the writer until the reader has consumed the value,
 * exercising the full suspension/resumption path on every message.
 */
class BenchChannel {
	static public function run():Array<BenchResult> {
		return [benchPingPong()];
	}

	static function benchPingPong():BenchResult {
		final n = BenchConfig.MEDIUM;
		return BenchRunner.measure("channel/pingpong", n, () -> {
			final ch = Channel.createBounded({size: 1});
			CoroRun.run(node -> {
				node.async(_ -> {
					for (i in 0...n)
						ch.write(i);
					ch.close();
				});
				final out = new Out();
				while (ch.waitForRead())
					while (ch.tryRead(out)) {}
			});
		});
	}
}
