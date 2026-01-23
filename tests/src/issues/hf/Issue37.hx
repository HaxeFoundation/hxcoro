package issues.hf;

import hxcoro.concurrent.AtomicInt;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.Out;
import hxcoro.CoroRun;
import hxcoro.Coro.*;

class Issue37 extends utest.Test {
	function test() {
		final numIterations = 2;
		final numTasks = 100;
		final expected = [for (i in 0...numIterations) numTasks];
		final actual = [];
		for (_ in 0...numIterations) {
			var aggregateValue = new AtomicInt(0);
			CoroRun.runScoped(node -> {
				timeout(3000, node -> {
					final channel = Channel.createBounded({size: 10});

					// set up writers
					var count = 0;
					for (_ in 0...numTasks) {
						node.async(_ -> {
							delay(1);

							channel.writer.write(1);

							if (++count == numTasks) {
								channel.writer.close();
							}
						});
					}

					// set up readers
					for (_ in 0...numTasks) {
						node.async(_ -> {
							final o = new Out();

							while (channel.reader.waitForRead()) {
								delay(1);
								if (channel.reader.tryRead(o)) {
									aggregateValue.add(o.get());
									break;
								} else {
									continue;
								}
							}
						});
					}

					node.awaitChildren();
				});
			});
			actual.push(aggregateValue.load());
		}
		utest.Assert.same(expected, actual);
	}
}