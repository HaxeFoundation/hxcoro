package structured;

import haxe.Exception;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.exceptions.CancellationException;

private class FunctionCancellationCallback implements ICancellationCallback {
	final f:CancellationException -> Void;

	public function new(f) {
		this.f = f;
	}

	public function onCancellation(cause:CancellationException) {
		f(cause);
	}
}

/**
	Exceptions from callbacks registered with a task must not stop the other callbacks or leave
	the task machinery half done. They are rethrown from a separately scheduled event instead.
**/
class TestCallbackExceptions extends atest.Test {
	static function messages(errors:Array<Exception>) {
		return [for (e in errors) e.message];
	}

	function testThrowingCompletionCallbackDoesNotStarveOthers() {
		final errors = [];
		var secondCalled = false;
		var awaited = false;
		final task = VirtualRun.run(node -> {
			final child = node.async(_ -> {
				delay(1);
				1;
			});
			child.onCompletion((_, _) -> throw new Exception("callback failure"));
			child.onCompletion((_, _) -> secondCalled = true);
			child.await();
			awaited = true;
			delay(5);
		}, 1000, errors.push);
		Assert.isFalse(task.isActive());
		Assert.isNull(task.getError());
		Assert.isTrue(secondCalled, "the second completion callback was never called");
		Assert.isTrue(awaited, "awaiting the task never resumed");
		Assert.same(["callback failure"], messages(errors), "the callback's exception was not reported");
	}

	function testThrowingCompletionCallbackOnCompletedTask() {
		final errors = [];
		var registered = false;
		final task = VirtualRun.run(node -> {
			final child = node.async(_ -> 1);
			child.await();
			child.onCompletion((_, _) -> throw new Exception("callback failure"));
			registered = true;
			delay(5);
		}, 1000, errors.push);
		Assert.isFalse(task.isActive());
		Assert.isTrue(registered, "onCompletion threw into its caller");
		Assert.same(["callback failure"], messages(errors));
	}

	/**
		`doCancel` runs the cancellation callbacks before it cancels the children and checks for
		completion, so an exception escaping a callback used to skip both.
	**/
	function testThrowingCancellationCallbackDoesNotStopCancellation() {
		final errors = [];
		var secondCalled = false;
		var cancelReturned = false;
		var grandchildCancelled = false;
		var childError:Null<Exception> = null;
		final task = VirtualRun.run(node -> {
			final child = node.async(child -> {
				final token = child.context.get(CancellationToken);
				token.onCancellationRequested(new FunctionCancellationCallback(_ -> throw new Exception("callback failure")));
				token.onCancellationRequested(new FunctionCancellationCallback(_ -> secondCalled = true));
				child.async(_ -> {
					try {
						delay(1000);
					} catch (e:CancellationException) {
						grandchildCancelled = true;
						throw e;
					}
				});
				delay(1000);
			});
			delay(1);
			child.cancel();
			cancelReturned = true;
			try {
				child.await();
			} catch (e:Exception) {
				childError = e;
			}
		}, 100, errors.push);
		Assert.isTrue(cancelReturned, "cancel() threw into its caller");
		Assert.isFalse(task.isActive(), "the task never completed");
		Assert.isTrue(secondCalled, "the second cancellation callback was never called");
		Assert.isTrue(grandchildCancelled, "the children were not cancelled");
		Assert.isOfType(childError, CancellationException);
		Assert.same(["callback failure"], messages(errors));
	}

	/**
		Same as `testThrowingCompletionCallbackDoesNotStarveOthers`, with the dispatcher that the
		test run uses, which is a thread pool on some targets. There, the exception is reported on a
		worker thread, and the run and the process must carry on.
	**/
	function testThrowingCompletionCallbackWithDefaultSetup() {
		var secondCalled = false;
		try {
			run(node -> {
				final child = node.async(_ -> {
					delay(1);
					1;
				});
				child.onCompletion((_, _) -> throw new Exception("callback failure"));
				child.onCompletion((_, _) -> secondCalled = true);
				child.await();
				delay(20);
			});
		} catch (e:Exception) {
			// On a single-threaded setup, the reported exception ends the run.
			Assert.equals("callback failure", e.message);
		}
		Assert.isTrue(secondCalled, "the second completion callback was never called");
	}

	/**
		Every throwing callback is reported, not just the first one.
	**/
	function testEveryThrowingCallbackIsReported() {
		final errors = [];
		final task = VirtualRun.run(node -> {
			final child = node.async(_ -> {
				delay(1);
				1;
			});
			child.onCompletion((_, _) -> throw new Exception("first"));
			child.onCompletion((_, _) -> throw new Exception("second"));
			child.await();
			delay(5);
		}, 1000, errors.push);
		Assert.isFalse(task.isActive());
		Assert.same(["first", "second"], messages(errors));
	}
}
