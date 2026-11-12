package structured;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.TimeoutException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.FailureCancellationException;
import hxcoro.task.ICoroTask;

/**
	`join` waits for a task like `await`, but neither returns its result nor throws its error. It only
	throws when the joining task itself is cancelled.
**/
class TestJoin extends atest.Test {
	function testJoinSucceededTask() {
		var active = true;
		var result = 0;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> {
				delay(10);
				42;
			});
			other.join();
			active = other.isActive();
			result = other.get();
		});
		Assert.isFalse(task.isActive());
		Assert.isFalse(active, "join returned before the task completed");
		Assert.equals(42, result);
	}

	function testJoinFailedTask() {
		var t:Null<ICoroTask<Any>> = null;
		var joined = false;
		final thrown = new Exception("boom");
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				t = s.async(_ -> {
					delay(10);
					throw thrown;
				});
				t.join();
				joined = true;
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(joined, "join threw the task's error");
		Assert.isTrue(t.isFailed());
		Assert.isTrue(t.getError() == thrown);
	}

	function testJoinCancelledTask() {
		var t:Null<ICoroTask<Any>> = null;
		var joined = false;
		final task = VirtualRun.run(node -> {
			t = node.async(_ -> awaitCancellation());
			yield();
			t.cancel();
			t.join();
			joined = true;
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(joined, "join threw the task's cancellation");
		Assert.isTrue(t.isCancelled());
	}

	function testJoinEscapedTimeout() {
		var t:Null<ICoroTask<Any>> = null;
		var joined = false;
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				t = s.async(_ -> timeout(10, _ -> awaitCancellation()));
				t.join();
				joined = true;
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(joined, "join threw the task's TimeoutException");
		Assert.isTrue(t.isFailed());
		Assert.isOfType(t.getError(), TimeoutException);
	}

	function testJoinStartsLazyTask() {
		var result = 0;
		final task = VirtualRun.run(node -> {
			final other = node.lazy(_ -> 42);
			other.join();
			result = other.get();
		});
		Assert.isFalse(task.isActive());
		Assert.equals(42, result);
	}

	function testJoinCompletedTask() {
		var joined = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> 42);
			yield();
			other.join();
			joined = true;
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(joined);
	}

	function testCancelJoiner() {
		var caught:Null<CancellationException> = null;
		var otherActive = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			final joiner = node.async(_ -> {
				try {
					other.join();
				} catch (e:CancellationException) {
					caught = e;
					throw e;
				}
			});
			yield();
			joiner.cancel();
			yield();
			yield();
			otherActive = other.isActive();
			other.cancel();
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(caught, "the joiner didn't react to cancellation");
		Assert.isTrue(otherActive, "cancelling the joiner affected the joined task");
	}

	function testCancelledJoinerLeavesAwaiters() {
		var awaiters:Null<Array<Any>> = null;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			final joiner = node.async(_ -> other.join());
			yield();
			joiner.cancel();
			yield();
			final otherTask:CoroBaseTask<Any> = cast other;
			awaiters = @:privateAccess otherTask.awaitingContinuations.handles;
			other.cancel();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(awaiters == null || awaiters.length == 0, "the cancelled joiner is still registered");
	}

	/**
		A parent joining its own failing child is cancelled by the failure, just like with `await`.
	**/
	function testJoinOnFailingChildThrowsFailureCancellation() {
		var caught:Null<FailureCancellationException> = null;
		var t:Null<ICoroTask<Any>> = null;
		final thrown = new Exception("boom");
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				t = s.async(p -> {
					final child = p.async(_ -> {
						yield();
						throw thrown;
					});
					try {
						child.join();
					} catch (e:FailureCancellationException) {
						caught = e;
						throw e;
					}
				});
			});
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(caught, "join didn't throw a FailureCancellationException");
		Assert.isTrue(caught.error == thrown);
		Assert.isTrue(t.isFailed());
		Assert.isTrue(t.getError() == thrown);
	}

	/**
		Joining tasks under a supervisor within a timeout: a failing task doesn't end the wait for the
		others, and the timeout still interrupts it.
	**/
	function testJoinInTimeout() {
		var timedOut = false;
		var slowCancelled = false;
		var fastSucceeded = false;
		final task = VirtualRun.run(node -> {
			supervisor(s -> {
				final failing = s.async(_ -> {
					delay(10);
					throw new Exception("boom");
				});
				final fast = s.async(_ -> {
					delay(20);
					1;
				});
				final slow = s.async(_ -> awaitCancellation());
				final requests:Array<ICoroTask<Any>> = [failing, fast, slow];
				try {
					timeout(100, _ -> {
						for (request in requests) {
							request.join();
						}
					});
				} catch (_:TimeoutException) {
					timedOut = true;
					for (request in requests) {
						request.cancel();
					}
				}
				slow.join();
				slowCancelled = slow.isCancelled();
				fastSucceeded = !fast.isActive() && !fast.isFailed() && !fast.isCancelled();
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(timedOut, "the timeout didn't interrupt the join");
		Assert.isTrue(fastSucceeded, "the failing task ended the wait for the others");
		Assert.isTrue(slowCancelled);
	}

	function testMultipleJoinersAndAwaiters() {
		var joins = 0;
		var result = 0;
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			final other = node.async(_ -> {
				latch.wait();
				42;
			});
			final joiners = [for (_ in 0...3) node.async(_ -> {
				other.join();
				joins++;
			})];
			yield();
			latch.arrive(1);
			result = other.await();
			for (joiner in joiners) {
				joiner.join();
			}
		});
		Assert.isFalse(task.isActive());
		Assert.equals(3, joins);
		Assert.equals(42, result);
	}
}
