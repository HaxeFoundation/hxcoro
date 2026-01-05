package issues.hf;

import hxcoro.ds.channels.Channel;
import hxcoro.ds.Out;
import hxcoro.CoroRun;
import hxcoro.Coro.*;

class Issue32 extends utest.Test {
	function test() {
		for (_ in 0...10) {
			final channel = Channel.createBounded({size: 3});
			final expected = [for (i in 0...100) i];
			final actual = [];

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
							});
						}
					});
				} catch(e:Dynamic) {
					trace(e);
					trace(channel, actual);
					throw e;
				}
			});

			utest.Assert.same(expected, actual);
		}
	}
}