package elements;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.elements.NonCancellable;
import hxcoro.TimeoutException;
import hxcoro.task.ICoroTask;

/**
	`NonCancellable` follows Kotlin's semantics: it is a boundary against cancellation coming from
	outside, not a flag that makes everything below it immune.

	- A task created with a new `NonCancellable` element is not cancelled when its parent is
	  cancelled, and `cancel()` on it is ignored. This holds for tasks created while the parent
	  is already cancelling, which is the cleanup use case.
	- Everything created inside it is an ordinary task: `timeout` fires, children can be cancelled
	  with `cancel()` and `cancelChildren()`, and that cancellation reaches their own children.
	- Only a new element starts a new boundary. A child that inherits the element from its
	  parent is not protected against that parent.
	- Failures are not cancellation. A failing child fails the task, cancels its siblings, and
	  the error reaches awaiters and the task's parent.
**/
class TestNonCancellable extends atest.Test {
	static function isBoom(e:Dynamic) {
		return Std.isOfType(e, Exception) && (cast e : Exception).message == "boom";
	}

	@:coroutine static function awaitCancelled(task:ICoroTask<Any>) {
		try {
			task.await();
		} catch (_:CancellationException) {}
	}

	function testSurvivesParentCancellation() {
		var cleanupRan = false;
		final task = VirtualRun.run(node -> {
			final child = node.async(n -> {
				try {
					awaitCancellation();
				} catch (e:CancellationException) {
					n.with(new NonCancellable()).async(_ -> {
						delay(10);
						cleanupRan = true;
					});
					throw e;
				}
			});
			yield();
			child.cancel();
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(cleanupRan, "the NonCancellable cleanup task didn't run to completion");
	}

	function testCancelIsIgnored() {
		var result = 0;
		var error:Dynamic = null;
		final task = VirtualRun.run(node -> {
			final t = node.with(new NonCancellable()).async(_ -> {
				delay(10);
				return 1;
			});
			t.cancel();
			result = t.await();
			error = t.getError();
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.equals(1, result);
		Assert.isNull(error, "cancel() cancelled a NonCancellable task");
	}

	function testTimeoutInsideFires() {
		var timedOut = false;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(_ -> {
				try {
					timeout(10, _ -> delay(100));
				} catch (_:TimeoutException) {
					timedOut = true;
				}
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(timedOut, "timeout inside a NonCancellable task didn't fire");
	}

	function testTimeoutInCleanupAfterCancellation() {
		var cleanupTimedOut = false;
		final task = VirtualRun.run(node -> {
			final child = node.async(n -> {
				try {
					awaitCancellation();
				} catch (e:CancellationException) {
					n.with(new NonCancellable()).async(_ -> {
						try {
							timeout(10, _ -> delay(100));
						} catch (_:TimeoutException) {
							cleanupTimedOut = true;
						}
					});
					throw e;
				}
			});
			yield();
			child.cancel();
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(cleanupTimedOut, "timeout in the cleanup task didn't fire");
	}

	function testChildCanBeCancelled() {
		var childActive = true;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(n -> {
				final child = n.async(_ -> awaitCancellation());
				yield();
				child.cancel();
				awaitCancelled(child);
				childActive = child.isActive();
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isFalse(childActive, "the child of a NonCancellable task could not be cancelled");
	}

	function testCancelChildrenCancelsChildren() {
		var activeChildren = -1;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(n -> {
				final children = [for (_ in 0...2) n.async(_ -> awaitCancellation())];
				yield();
				n.cancelChildren();
				n.awaitChildren();
				activeChildren = 0;
				for (child in children) {
					if (child.isActive()) {
						activeChildren++;
					}
				}
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.equals(0, activeChildren, "cancelChildren() didn't cancel the children of a NonCancellable task");
	}

	function testGrandchildIsCancelledWithChild() {
		var grandchild:Null<ICoroTask<Any>> = null;
		var grandchildActive = true;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(n -> {
				final child = n.async(c -> {
					grandchild = c.async(_ -> awaitCancellation());
					awaitCancellation();
				});
				yield();
				yield();
				child.cancel();
				awaitCancelled(child);
				grandchildActive = grandchild.isActive();
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isFalse(grandchildActive, "cancelling the child didn't cancel the grandchild");
	}

	function testNestedElementIsNewBoundary() {
		var protectedRan = false;
		var plainActive = true;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(n -> {
				final plain = n.async(_ -> awaitCancellation());
				final protected = n.with(new NonCancellable()).async(_ -> {
					delay(10);
					protectedRan = true;
				});
				yield();
				n.cancelChildren();
				awaitCancelled(plain);
				protected.await();
				plainActive = plain.isActive();
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isFalse(plainActive, "the child that inherited the element was not cancelled");
		Assert.isTrue(protectedRan, "the child with its own element was cancelled");
	}

	function testChildFailureFailsTask() {
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			t = node.with(new NonCancellable()).async(n -> {
				n.async(_ -> {
					yield();
					throw new Exception("boom");
				});
				delay(10);
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isFalse(t.isActive(), "the NonCancellable task never completed");
		Assert.isTrue(isBoom(t.getError()), 'expected the child\'s exception, got ${t.getError()}');
	}

	function testChildFailureCancelsSiblings() {
		var sibling:Null<ICoroTask<Any>> = null;
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			t = node.with(new NonCancellable()).async(n -> {
				sibling = n.async(_ -> awaitCancellation());
				n.async(_ -> {
					yield();
					throw new Exception("boom");
				});
				awaitCancellation();
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isFalse(sibling.isActive(), "the failing child didn't cancel its sibling");
		Assert.isTrue(isBoom(t.getError()), 'expected the child\'s exception, got ${t.getError()}');
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
