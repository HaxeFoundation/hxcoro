package review;

/**
	Known failures from the 1.0 review: task outcome bookkeeping.
**/
class TestTaskOutcome extends atest.Test {
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
