package structured;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.elements.NonCancellable;
import hxcoro.task.ICoroTask;

/**
	How a child's outcome affects its parent: a cancelled child never does, a failing child fails
	the parent as soon as the failure is recorded, not only once the child has completed.
**/
class TestChildOutcomes extends atest.Test {
	static function isBoom(e:Null<Exception>) {
		return e != null && e.message == "boom";
	}

	function testCancelChildrenDoesNotCancelAsyncNode() {
		var t:Null<ICoroTask<Int>> = null;
		VirtualRun.run(node -> {
			t = node.async(n -> {
				n.async(_ -> awaitCancellation());
				n.async(_ -> awaitCancellation());
				yield();
				n.cancelChildren();
				return 42;
			});
		});
		Assert.isFalse(t.isActive());
		Assert.isNull(t.getError());
		Assert.equals(42, t.get());
	}

	function testCancelChildDoesNotCancelAsyncNode() {
		var t:Null<ICoroTask<Int>> = null;
		VirtualRun.run(node -> {
			t = node.async(n -> {
				final child = n.async(_ -> awaitCancellation());
				yield();
				child.cancel();
				return 42;
			});
		});
		Assert.isFalse(t.isActive());
		Assert.isNull(t.getError());
		Assert.equals(42, t.get());
	}

	function testCancelledChildDoesNotCancelScope() {
		var result = 0;
		final task = VirtualRun.run(node -> {
			result = scope(n -> {
				final child = n.async(_ -> awaitCancellation());
				yield();
				child.cancel();
				return 42;
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isNull(task.getError());
		Assert.equals(42, result);
	}

	/**
		The failing child has a `NonCancellable` grandchild that only completes once the sibling has
		been cancelled. If the parent only learned about the failure when the child completed, the
		sibling would never be cancelled and the run would hang.
	**/
	function testChildFailureCancelsSiblingsBeforeChildCompletes() {
		var t:Null<ICoroTask<Any>> = null;
		var siblingCancelled = false;
		var grandchildCompleted = false;
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				t = s.async(p -> {
					final siblingCancelledLatch = new CoroLatch(1);
					p.async(_ -> {
						try {
							awaitCancellation();
						} catch (e:CancellationException) {
							siblingCancelled = true;
							siblingCancelledLatch.arrive(1);
							throw e;
						}
					});
					p.async(c -> {
						c.with(new NonCancellable()).async(_ -> {
							siblingCancelledLatch.wait();
							grandchildCompleted = true;
						});
						yield();
						throw new Exception("boom");
					});
					awaitCancellation();
				});
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(siblingCancelled, "the sibling was not cancelled");
		Assert.isTrue(grandchildCompleted, "the grandchild never completed");
		Assert.isTrue(t.isFailed());
		Assert.isTrue(isBoom(t.getError()), 'expected the child\'s exception, got ${t.getError()}');
	}

	/**
		A child that fails while it is being cancelled reports that failure, even though the parent
		asked for the cancellation and is not cancelling itself.
	**/
	function testChildFailureWhileCancellingFailsParent() {
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				t = s.async(p -> {
					final child = p.async(_ -> {
						try {
							awaitCancellation();
						} catch (_:CancellationException) {
							throw new Exception("boom");
						}
					});
					yield();
					child.cancel();
					awaitCancellation();
				});
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(t.isFailed());
		Assert.isTrue(isBoom(t.getError()), 'expected the child\'s exception, got ${t.getError()}');
	}

	function testCancelledChildIsReportedToAwaiter() {
		var awaitError:Null<Exception> = null;
		var t:Null<ICoroTask<Int>> = null;
		VirtualRun.run(node -> {
			t = node.async(n -> {
				final child = n.async(_ -> awaitCancellation());
				yield();
				child.cancel();
				try {
					child.await();
				} catch (e:CancellationException) {
					awaitError = e;
				}
				return 42;
			});
		});
		Assert.isFalse(t.isActive());
		Assert.equals(42, t.get());
		Assert.isOfType(awaitError, CancellationException);
	}
}
