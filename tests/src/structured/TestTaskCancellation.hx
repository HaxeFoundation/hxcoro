package structured;

import hxcoro.dispatchers.TrampolineDispatcher;
import haxe.exceptions.CancellationException;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationCallback;

class ResultPusherHandle implements ICancellationCallback {
	final result:Array<Int>;

	public function new(result:Array<Int>) {
		this.result = result;
	}

	public function onCancellation(cause:CancellationException) {
		result.push(0);
	}
}

class TestTaskCancellation extends atest.Test {
	public function test_cancellation_callback() {
		final result     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			node.context.get(CancellationToken).onCancellationRequested(new ResultPusherHandle(result));

			delay(1000);
		});

		task.start();
		task.cancel();

		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		Assert.same([ 0 ], result);
	}

	public function test_closing_cancellation_callback() {
		var handle : ICancellationHandle = null;

		final result     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			handle = node.context.get(CancellationToken).onCancellationRequested(new ResultPusherHandle(result));

			delay(1000);
		});

		task.start();

		scheduler.advanceBy(1);

		handle.close();

		scheduler.advanceBy(1);

		task.cancel();

		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		Assert.same([], result);
	}

	public function testChildrenReceiveCancellationCause() {
		final cause = new CancellationException();
		var childError:Dynamic = null;
		var parentError:Dynamic = null;
		final task = VirtualRun.run(node -> {
			supervisor(node -> {
				var child = null;
				final parent = node.async(node -> {
					child = node.async(_ -> delay(1000));
					delay(1000);
				});
				delay(10);
				parent.cancel(cause);
				try {
					parent.await();
				} catch (e:Dynamic) {
					parentError = e;
				}
				childError = child?.getError();
			});
		});
		Assert.isFalse(task.isActive());
		Assert.equals(cause, parentError);
		Assert.equals(cause, childError);
	}

	public function testCancelAfterCompletionKeepsResult() {
		var secondResult:Null<Int> = null;
		var secondError:Dynamic = null;
		var childError:Dynamic = null;
		final task = VirtualRun.run(node -> {
			final child = node.async(_ -> 42);
			child.await();
			child.cancel();
			childError = child.getError();
			try {
				secondResult = child.await();
			} catch (e:Dynamic) {
				secondError = e;
			}
		});
		Assert.isFalse(task.isActive());
		Assert.isNull(childError, "cancel() changed the error of a completed task");
		Assert.isNull(secondError, "awaiting a completed task threw after cancel()");
		Assert.equals(42, secondResult);
	}
}