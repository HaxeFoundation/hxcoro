package review;

/**
	Known failures from the 1.0 review: `CancellingContinuation`.
**/
class TestCancellingContinuation extends atest.Test {
	/**
		The setter of `onCancellationRequested` calls the cleanup callback whenever the token is
		cancelled, even if the continuation was already resumed normally. On a thread pool this
		happens when another thread resumes the continuation and then cancels the task before
		`suspendCancellable` installs the callback. The channels then remove a waiter that was
		already popped, which corrupts their waiter queues.
	**/
	function testCleanupNotCalledAfterNormalResume() {
		var cleanupCalled = false;
		var result = 0;
		final task = VirtualRun.run(node -> {
			final child = node.async(child -> {
				result = suspendCancellable(cont -> {
					cont.resume(1, null);
					child.cancel();
					_ -> cleanupCalled = true;
				});
			});
			try {
				child.await();
			} catch (_:Dynamic) {}
		});
		Assert.isFalse(task.isActive());
		Assert.equals(1, result);
		Assert.isFalse(cleanupCalled, "cleanup ran for a continuation that was resumed normally");
	}
}
