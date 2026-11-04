package structured;

import haxe.exceptions.CancellationException;
import hxcoro.TimeoutException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;

/**
	`await` is cancellable: a cancelled awaiter stops waiting, leaves the awaited task alone and is
	removed from its awaiters. `onCompletion` returns a handle for the same purpose.
**/
class TestAwait extends atest.Test {
	function testAwaitInTimeout() {
		var timedOut = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			try {
				timeout(100, _ -> other.await());
			} catch (_:TimeoutException) {
				timedOut = true;
			}
			other.cancel();
		});
		Assert.isTrue(timedOut, "the timeout didn't interrupt the await");
		Assert.isFalse(task.isActive());
	}

	function testCancelAwaiter() {
		var awaiterActive = true;
		var otherActive = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			final awaiter = node.async(_ -> other.await());
			yield();
			awaiter.cancel();
			yield();
			yield();
			awaiterActive = awaiter.isActive();
			otherActive = other.isActive();
			other.cancel();
		});
		Assert.isFalse(awaiterActive, "the awaiter didn't react to cancellation");
		Assert.isTrue(otherActive, "cancelling the awaiter affected the awaited task");
		Assert.isFalse(task.isActive());
	}

	function testCancelledAwaiterLeavesAwaiters() {
		var awaiters:Null<Array<Any>> = null;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			final awaiter = node.async(_ -> other.await());
			yield();
			awaiter.cancel();
			yield();
			final otherTask:CoroBaseTask<Any> = cast other;
			awaiters = @:privateAccess otherTask.awaitingContinuations.handles;
			other.cancel();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(awaiters == null || awaiters.length == 0, "the cancelled awaiter is still registered");
	}

	function testAwaitedTaskCompletesAfterAwaiterWasCancelled() {
		var awaiterCancelled = false;
		var result = 0;
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			final other = node.async(_ -> {
				latch.wait();
				42;
			});
			final awaiter = node.async(_ -> other.await());
			yield();
			awaiter.cancel();
			yield();
			awaiterCancelled = awaiter.isCancelled();
			latch.arrive(1);
			result = other.await();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(awaiterCancelled);
		Assert.equals(42, result);
	}

	function testAwaitOnCompletedTask() {
		var result = 0;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> 42);
			yield();
			result = other.await();
		});
		Assert.isFalse(task.isActive());
		Assert.equals(42, result);
	}

	function testOnCompletionHandleClose() {
		var called = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> delay(10));
			final handle = other.onCompletion((_, _) -> called = true);
			Assert.notNull(handle);
			handle.close();
			other.await();
		});
		Assert.isFalse(task.isActive());
		Assert.isFalse(called, "the closed completion callback ran");
	}

	function testOnCompletionOnCompletedTask() {
		var called = false;
		var handle:Null<Any> = null;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> 42);
			other.await();
			handle = other.onCompletion((_, _) -> called = true);
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(called, "the callback didn't run on a completed task");
		Assert.isNull(handle);
	}
}
