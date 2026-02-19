package issues.hf;

import hxcoro.concurrent.CoroLatch;
import haxe.coro.Mutex;
import haxe.exceptions.CancellationException;

class Issue64 extends utest.Test {
	function test() {
		final cause = new CancellationException();
		final cancellations = [];
		final mutex = new Mutex();
		CoroRun.run(node -> {
			for (i in 0...5) {
				final latch = new CoroLatch(5);
				for (k in 0...5) {
					node.async(node -> {
						try {
							latch.arrive(1);
							delay(5000000);
						} catch(e:CancellationException) {
							mutex.acquire();
							cancellations[i * 5 + k] = e;
							mutex.release();
							throw e;
						}
					});
				}
				latch.wait();
				node.cancelChildren(cause);
				node.awaitChildren();
			}
		});
		Assert.equals(25, cancellations.length);
		for (i in 0...25) {
			Assert.equals(cause, cancellations[i]);
		}
	}
}