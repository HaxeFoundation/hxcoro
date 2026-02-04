package issues.hf;

import hxcoro.concurrent.AtomicInt;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.Out;
import hxcoro.CoroRun;
import hxcoro.Coro.*;

class Issue37 extends utest.Test {
	#if false // everyone hates this
	function testCancelling() {
		final numIterations = 2;
		final numTasks = 100;
		final expected = [for (i in 0...numIterations) numTasks];
		final actual = [];
		for (_ in 0...numIterations) {
			var aggregateValue = new AtomicInt(0);
			CoroRun.run(node -> {
				final channel = Channel.createBounded({size: 10});

				// set up writers
				var count = new AtomicInt(0);
				for (_ in 0...numTasks) {
					node.async(_ -> {
						delay(1);

						channel.writer.write(1);

						if (count.add(1) == numTasks - 1) {
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
			actual.push(aggregateValue.load());
		}
		utest.Assert.same(expected, actual);
	}

	function testNotCancelling() {
		final numIterations = 2;
		final numTasks = 100;
		final expected = [for (i in 0...numIterations) numTasks];
		final actual = [];
		for (_ in 0...numIterations) {
			var aggregateValue = new AtomicInt(0);
			CoroRun.run(node -> {
				final channel = Channel.createBounded({size: 10});

				// set up writers
				for (_ in 0...numTasks) {
					node.async(_ -> {
						delay(1);

						channel.writer.write(1);
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
			actual.push(aggregateValue.load());
		}
		utest.Assert.same(expected, actual);
	}

	function testRacing() {
		final numIterations = 2;
		final numTasks = 100;
		final expected = [for (i in 0...numIterations) numTasks];
		final actual = [];
		for (_ in 0...numIterations) {
			var aggregateValue = new AtomicInt(0);
			CoroRun.run(node -> {
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
			actual.push(aggregateValue.load());
		}
		utest.Assert.same(expected, actual);
	}
	#end
}