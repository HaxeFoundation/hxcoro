package elements;

import haxe.Exception;
import hxcoro.elements.NonCancellable;

class TestNonCancellable extends atest.Test {
	static function isBoom(e:Dynamic) {
		return Std.isOfType(e, Exception) && (cast e : Exception).message == "boom";
	}

	function testFailureIsReportedToAwaiter() {
		var awaitReturned = false;
		var awaitError:Dynamic = null;
		final task = VirtualRun.run(node -> {
			supervisor(node -> {
				final child = node.with(new NonCancellable()).async(_ -> {
					yield();
					throw new Exception("boom");
				});
				try {
					child.await();
					awaitReturned = true;
				} catch (e:Dynamic) {
					awaitError = e;
				}
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isFalse(awaitReturned, "await on a failed NonCancellable task returned normally");
		Assert.isTrue(isBoom(awaitError), 'expected the child\'s exception, got $awaitError');
	}

	function testFailurePropagatesToParent() {
		var task = null;
		try {
			task = VirtualRun.run(node -> {
				node.with(new NonCancellable()).async(_ -> {
					yield();
					throw new Exception("boom");
				});
			});
		} catch (e:Dynamic) {
			Assert.fail('running the task crashed with $e');
			return;
		}
		Assert.isFalse(task.isActive());
		Assert.isTrue(isBoom(task.getError()), 'expected the child\'s exception, got ${task.getError()}');
	}
}
