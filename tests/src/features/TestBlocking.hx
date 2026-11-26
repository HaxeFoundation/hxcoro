package features;

import haxe.Exception;

class TestBlocking extends atest.Test {
	function testResult() {
		Assert.equals(3, run(_ -> blocking(() -> 1 + 2)));
	}

	function testException() {
		final message = run(_ -> {
			try {
				blocking(() -> throw new Exception("failed"));
				"no exception";
			} catch (e:Exception) {
				e.message;
			}
		});
		Assert.equals("failed", message);
	}

	function testFromChildren() {
		final sum = run(node -> {
			final tasks = [for (i in 0...20) node.async(_ -> blocking(() -> i))];
			var sum = 0;
			for (task in tasks) {
				sum += task.await();
			}
			sum;
		});
		Assert.equals(190, sum);
	}
}
