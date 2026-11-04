package structured;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.elements.NonCancellable;
import hxcoro.TimeoutException;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;

/**
	How a task's cause is recorded: cancellation versus failure, failures that happen while
	cancelling.
**/
class TestStopCause extends atest.Test {
	function testCancelledTask() {
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			t = node.async(_ -> awaitCancellation());
			yield();
			t.cancel();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(t.isCancelled());
		Assert.isFalse(t.isFailed());
		Assert.isOfType(t.getError(), CancellationException);
	}

	function testFailedTask() {
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(_ -> {
					yield();
					throw new Exception("boom");
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(t.isFailed());
		Assert.isFalse(t.isCancelled());
		Assert.equals("boom", t.getError().message);
	}

	/**
		A `CancellationException` that nobody requested is a failure. Here the child's own `timeout`
		escapes its body, so the child fails and the scope rethrows the `TimeoutException`.
	**/
	function testEscapedTimeoutFailsScope() {
		var caught:Null<Exception> = null;
		final task = VirtualRun.run(node -> {
			try {
				scope(n -> {
					n.async(_ -> timeout(10, _ -> delay(100)));
					n.awaitChildren();
				});
			} catch (e:TimeoutException) {
				caught = e;
			}
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(caught, "the escaped TimeoutException was swallowed");
	}

	/**
		Awaiting a task that was cancelled throws its `CancellationException` into the awaiter, which
		did not request cancellation, so the awaiter fails and the scope rethrows.
	**/
	function testAwaitingCancelledTaskFailsScope() {
		var caught:Null<Exception> = null;
		final task = VirtualRun.run(node -> {
			try {
				scope(n -> {
					final other = n.async(_ -> awaitCancellation());
					n.async(_ -> other.await());
					yield();
					other.cancel();
				});
			} catch (e:CancellationException) {
				caught = e;
			}
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(caught, "the awaiter's CancellationException was swallowed");
	}

	/**
		A failure while cancelling replaces the cancellation as the task's cause.
	**/
	function testFailureDuringCancellationReplacesCause() {
		var t:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(_ -> {
					try {
						awaitCancellation();
					} catch (e:CancellationException) {
						throw new Exception("cleanup failed");
					}
				});
				yield();
				t.cancel();
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.isFalse(t.isCancelled());
		Assert.equals("cleanup failed", t.getError().message);
	}

	/**
		A child that fails while its parent is cancelling fails the parent.
	**/
	function testChildFailureDuringCancellationFailsParent() {
		var t:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					p.async(_ -> {
						try {
							awaitCancellation();
						} catch (e:CancellationException) {
							throw new Exception("child cleanup failed");
						}
					});
					awaitCancellation();
				});
				yield();
				yield();
				t.cancel();
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.equals("child cleanup failed", t.getError().message);
	}

	/**
		A second failure does not replace the first.
	**/
	function testFirstFailureWins() {
		var t:Null<ICoroTask<Any>> = null;
		final a = new Exception("a");
		final b = new Exception("b");
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					p.async(_ -> {
						yield();
						throw a;
					});
					try {
						awaitCancellation();
					} catch (e:CancellationException) {
						throw b;
					}
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.equals(a, t.getError());
	}

	/**
		The children of a failed task are all cancelled with the same cause object.
	**/
	function testChildrenShareCancellationCause() {
		var t:Null<ICoroTask<Any>> = null;
		var c1:Null<ICoroTask<Any>> = null;
		var c2:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					c1 = p.async(_ -> awaitCancellation());
					c2 = p.async(_ -> awaitCancellation());
					yield();
					throw new Exception("boom");
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(c1.isCancelled());
		Assert.isTrue(c2.isCancelled());
		Assert.isTrue(c1.getError() == c2.getError(), "the children have different cancellation causes");
		final parent:CoroBaseTask<Any> = cast t;
		Assert.isTrue(c1.getError() == parent.cancellationException, "the children's cause is not the parent's");
	}

	/**
		The sibling of a child that failed from an escaped timeout is cancelled with a plain
		`CancellationException`, not with the `TimeoutException`, which it never had. The parent still
		reports the `TimeoutException` as its error.
	**/
	function testSiblingOfTimedOutChildIsNotCancelledWithTimeout() {
		var t:Null<ICoroTask<Any>> = null;
		var sibling:Null<ICoroTask<Any>> = null;
		var siblingCaught:Null<Exception> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					sibling = p.async(_ -> {
						try {
							awaitCancellation();
						} catch (e:CancellationException) {
							siblingCaught = e;
							throw e;
						}
					});
					p.async(_ -> timeout(10, _ -> delay(100)));
					awaitCancellation();
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.isOfType(t.getError(), TimeoutException);
		Assert.isTrue(sibling.isCancelled());
		Assert.notNull(siblingCaught);
		Assert.isFalse(Std.isOfType(siblingCaught, TimeoutException), "the sibling was cancelled with a timeout it never had");
		Assert.isFalse(Std.isOfType(sibling.getError(), TimeoutException));
		final parent:CoroBaseTask<Any> = cast t;
		Assert.isTrue(sibling.getError() == parent.cancellationException, "the sibling's cause is not the parent's");
	}

	/**
		When a cancelling task is upgraded to a failure, its cancellation cause stays what it was: the
		children and the callbacks have received it already.
	**/
	function testUpgradeKeepsCancellationCause() {
		var t:Null<ICoroTask<Any>> = null;
		var child:Null<ICoroTask<Any>> = null;
		final cause = new CancellationException();
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					child = p.async(_ -> awaitCancellation());
					try {
						awaitCancellation();
					} catch (e:CancellationException) {
						throw new Exception("cleanup failed");
					}
				});
				yield();
				yield();
				t.cancel(cause);
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.equals("cleanup failed", t.getError().message);
		final parent:CoroBaseTask<Any> = cast t;
		Assert.isTrue(parent.cancellationException == cause, "the upgrade replaced the cancellation cause");
		Assert.isTrue(child.isCancelled());
		Assert.isTrue(child.getError() == cause, "the child was not cancelled with the original cause");
	}

	/**
		A task that inherits a child's failure reuses the child's cause, so the child's own children
		and the child's siblings are all cancelled with the same cause object.
	**/
	function testInheritedFailureSharesCauseAcrossTree() {
		var t:Null<ICoroTask<Any>> = null;
		var sibling:Null<ICoroTask<Any>> = null;
		var grandchild:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.async(p -> {
					sibling = p.async(_ -> awaitCancellation());
					p.async(a -> {
						grandchild = a.async(_ -> awaitCancellation());
						yield();
						throw new Exception("boom");
					});
					awaitCancellation();
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.equals("boom", t.getError().message);
		Assert.isTrue(grandchild.isCancelled());
		Assert.isTrue(sibling.isCancelled());
		Assert.isTrue(grandchild.getError() == sibling.getError(), "the grandchild and the sibling have different causes");
		final parent:CoroBaseTask<Any> = cast t;
		Assert.isTrue(sibling.getError() == parent.cancellationException, "the sibling's cause is not the parent's");
	}

	/**
		Only cancellation is gated by `NonCancellable`: a failing child fails the task.
	**/
	function testChildFailureFailsNonCancellableTask() {
		var t:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor(n -> {
				t = n.with(new NonCancellable()).async(p -> {
					p.async(_ -> {
						yield();
						throw new Exception("boom");
					});
					delay(10);
				});
				try {
					t.await();
				} catch (_:Exception) {}
			});
		});
		Assert.isTrue(t.isFailed());
		Assert.equals("boom", t.getError().message);
	}
}
