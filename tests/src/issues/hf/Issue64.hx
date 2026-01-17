package issues.hf;

import haxe.exceptions.CancellationException;

class Issue64 extends utest.Test {
	function test() {
		final cause = new CancellationException();
		final cancellations = [];
		CoroRun.runScoped(node -> {
			for (i in 0...5) {
				for (k in 0...5) {
					node.async(node -> {
						try {
							delay(500000);
						} catch(e:CancellationException) {
							cancellations[i * 5 + k] = e;
							throw e;
						}
					});
				}
				delay(1);
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