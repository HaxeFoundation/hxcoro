package issues.hf;

import haxe.coro.Mutex;
import haxe.exceptions.CancellationException;

class Issue64 extends utest.Test {
	function test() {
		final cause = new CancellationException();
		final cancellations = [];
		final mutex = new Mutex();
		CoroRun.runScoped(node -> {
			for (i in 0...5) {
				#if target.threaded
				final semaphore = new sys.thread.Semaphore(0);
				#end
				for (k in 0...5) {
					node.async(node -> {
						try {
							#if target.threaded
							semaphore.release();
							#end
							delay(5000000);
						} catch(e:CancellationException) {
							mutex.acquire();
							cancellations[i * 5 + k] = e;
							mutex.release();
							throw e;
						}
					});
				}
				#if target.threaded
				for (_ in 0...5) {
					semaphore.acquire();
				}
				#end
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