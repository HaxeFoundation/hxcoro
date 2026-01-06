package issues.hf;

import hxcoro.ds.channels.bounded.BoundedWriter;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.Out;
import hxcoro.CoroRun;
import hxcoro.Coro.*;

class Issue32 extends utest.Test {
	function test() {
		for (_ in 0...100) {
			final channel = Channel.createBounded({size: 3});
			final expected = [for (i in 0...100) i];
			final actual = [];
			var completedReaders = 0;

			CoroRun.runScoped(node -> {
				try {
					timeout(1000, node -> {
						node.async(_ -> {
							for (v in expected) {
								channel.write(v);
							}

							channel.close();
						});

						for (_ in 0...5) {
							node.async(_ -> {
								final out = new Out();

								while (channel.waitForRead()) {
									if (channel.tryRead(out)) {
										actual.push(out.get());
									}
								}
								++completedReaders;
							});
						}
					});
				} catch(e:Dynamic) {
					var writer:BoundedWriter<Int> = cast channel.writer;
					trace(@:privateAccess writer.closed.get());
					trace(@:privateAccess writer.writeWaiters.isEmpty());
					trace(actual.length);
					trace('Completed readers', completedReaders);
					trace(channel.waitForRead());
					throw e;
				}
			});

			utest.Assert.same(expected, actual);
		}
	}
}