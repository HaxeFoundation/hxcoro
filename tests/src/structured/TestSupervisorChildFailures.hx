package structured;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.TimeoutException;
import hxcoro.task.ICoroTask;

class TestSupervisorChildFailures extends atest.Test {
	static function messages(errors:Array<Exception>) {
		return [for (e in errors) e.message];
	}

	function testFailedChildIsReported() {
		final errors = [];
		final task = VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				node.async(_ -> throw new Exception("child failure"));
				"ok";
			});
		});
		Assert.equals("ok", task.get());
		Assert.same(["child failure"], messages(errors));
	}

	function testFailedChildIsPassed() {
		var reported:Null<ICoroTask<Any>> = null;
		var failing:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			supervisor((child, _) -> reported = child, node -> {
				node.async(_ -> delay(5));
				failing = node.async(_ -> throw new Exception("child failure"));
			});
		});
		Assert.notNull(reported);
		Assert.equals(failing, reported);
	}

	function testWithoutCallback() {
		final task = VirtualRun.run(node -> {
			supervisor(node -> {
				node.async(_ -> throw new Exception("child failure"));
				"ok";
			});
		});
		Assert.equals("ok", task.get());
	}

	function testChildFailingAfterBodyIsReported() {
		final errors = [];
		final task = VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				node.async(_ -> {
					delay(10);
					throw new Exception("late failure");
				});
				"ok";
			});
		});
		Assert.equals("ok", task.get());
		Assert.same(["late failure"], messages(errors));
	}

	function testEachFailureIsReportedOnce() {
		final errors = [];
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				node.async(_ -> throw new Exception("a"));
				node.async(_ -> {
					delay(5);
					throw new Exception("b");
				});
				node.async(_ -> delay(10));
			});
		});
		Assert.same(["a", "b"], messages(errors));
	}

	function testAwaitedChildIsReported() {
		final errors = [];
		var caught:Null<Exception> = null;
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				final child = node.async(_ -> {
					delay(1);
					throw new Exception("child failure");
				});
				try {
					child.await();
				} catch (e:Exception) {
					caught = e;
				}
			});
		});
		Assert.equals("child failure", caught?.message);
		Assert.same(["child failure"], messages(errors));
	}

	function testGrandchildFailureIsReportedOnce() {
		final errors = [];
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				node.async(child -> {
					child.async(_ -> throw new Exception("grandchild failure"));
					delay(10);
				});
			});
		});
		Assert.same(["grandchild failure"], messages(errors));
	}

	function testEscapedTimeoutIsReported() {
		final errors = [];
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				node.async(_ -> timeout(1, _ -> delay(10)));
			});
		});
		Assert.equals(1, errors.length);
		Assert.isOfType(errors[0], TimeoutException);
	}

	function testCancelledChildIsNotReported() {
		final errors = [];
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				final child = node.async(_ -> delay(10));
				delay(1);
				child.cancel();
			});
		});
		Assert.same([], errors);
	}

	function testChildrenCancelledByFailingBodyAreNotReported() {
		final errors = [];
		var thrown:Null<Exception> = null;
		VirtualRun.run(node -> {
			try {
				supervisor((_, e) -> errors.push(e), node -> {
					node.async(_ -> delay(10));
					delay(1);
					throw new Exception("body failure");
				});
			} catch (e:Exception) {
				thrown = e;
			}
		});
		Assert.equals("body failure", thrown?.message);
		Assert.same([], errors);
	}

	function testChildFailingWhileCancelledIsReported() {
		final errors = [];
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				final child = node.async(_ -> {
					try {
						delay(10);
					} catch (e:CancellationException) {
						throw new Exception("cleanup failure");
					}
				});
				delay(1);
				child.cancel();
			});
		});
		Assert.same(["cleanup failure"], messages(errors));
	}

	function testSequentialChildIsNotReported() {
		final errors = [];
		var caught:Null<Exception> = null;
		VirtualRun.run(node -> {
			supervisor((_, e) -> errors.push(e), node -> {
				try {
					scope(_ -> throw new Exception("scope failure"));
				} catch (e:Exception) {
					caught = e;
				}
			});
		});
		Assert.equals("scope failure", caught?.message);
		Assert.same([], errors);
	}

	function testThrowingCallbackIsReportedSeparately() {
		final dispatcherErrors = [];
		var otherChildDone = false;
		final task = VirtualRun.run(node -> {
			supervisor((_, _) -> throw new Exception("callback failure"), node -> {
				node.async(_ -> throw new Exception("child failure"));
				node.async(_ -> {
					delay(5);
					otherChildDone = true;
				});
				"ok";
			});
		}, 1000, dispatcherErrors.push);
		Assert.equals("ok", task.get());
		Assert.isTrue(otherChildDone);
		Assert.same(["callback failure"], messages(dispatcherErrors));
	}
}
