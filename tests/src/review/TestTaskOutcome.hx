package review;

import haxe.Exception;
import hxcoro.elements.NonCancellable;

/**
	Known failures from the 1.0 review: task outcome bookkeeping.
**/
class TestTaskOutcome extends atest.Test {
	static function isBoom(e:Dynamic) {
		return Std.isOfType(e, Exception) && (cast e : Exception).message == "boom";
	}

	/**
		`beginCancelling` moves the task to `Cancelling` before calling `doCancel`, and the
		`NonCancellable` override of `doCancel` returns before the error is stored. The task
		then completes as `Cancelled` with a null error, so the awaiter sees a success.
	**/
	function testNonCancellableFailureIsReportedToAwaiter() {
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

	/**
		Same as above, but the parent's `childErrors` receives the null error and its `doCancel`
		dereferences it.
	**/
	function testNonCancellableFailurePropagatesToParent() {
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

	/**
		A lazy child that is added after the parent's lambda returned is never started, because
		`startChildren` already ran. The parent then waits for it forever.
	**/
	function testLazyChildAddedAfterParentReturnedDoesNotHang() {
		var lazyRan = false;
		final task = VirtualRun.run(node -> {
			// Escapes the restricted scope, as storing the node in a field would.
			final root:hxcoro.task.ICoroNode.ICoroNodeWith = node;
			node.async(_ -> {
				delay(10);
				root.lazy(_ -> {
					lazyRan = true;
				});
			});
			// The root lambda returns here, before the lazy child exists.
		});
		Assert.isFalse(task.isActive(), "the parent never completed");
		Assert.isTrue(lazyRan, "the late lazy child was never started");
	}
}
