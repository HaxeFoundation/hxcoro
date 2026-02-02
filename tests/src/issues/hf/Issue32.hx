package issues.hf;

import haxe.coro.Mutex;
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
			final mutex = new Mutex();

			CoroRun.run(node -> {
				try {
					timeout(10000, node -> {
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
										mutex.acquire();
										actual.push(out.get());
										mutex.release();
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

			actual.sort(Reflect.compare);
			utest.Assert.same(expected, actual);
		}
	}
}