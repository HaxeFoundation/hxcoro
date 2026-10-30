package structured;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.exceptions.ArgumentException;
import haxe.exceptions.CancellationException;

class TestCancellingSuspend extends atest.Test {
	function test_callback() {
		final actual     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			timeout(100, _ -> {
				suspendCancellable(cont -> {
					_ -> {
						actual.push(scheduler.now());
					}
				});
			});
		});

		task.start();

		scheduler.advanceBy(100);

		Assert.equals(1, actual.length);
		Assert.isTrue(100i64 == actual[0]);
		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), CancellationException);
	}

	function test_resuming_successfully() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			AssertAsync.raises(() -> {
				suspendCancellable(cont -> {
					cont.context.scheduleFunction(0, () -> {
						cont.resume(null, null);
					});
					null;
				});
			}, CancellationException);
		});

		task.start();
		task.cancel();

		scheduler.advanceBy(0);

		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), CancellationException);
	}

	function test_failing() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			AssertAsync.raises(() -> {
				suspendCancellable(cont -> {
					cont.context.scheduleFunction(0, () -> {
						cont.resume(null, new ArgumentException(''));
					});
					null;
				});
			}, CancellationException);
		});

		task.start();
		task.cancel();

		scheduler.advanceBy(0);

		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), CancellationException);
	}

	function test_callback_is_unregistered() {
		final actual     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			suspendCancellable(cont -> {
				cont.resume(null, null);
				_ -> {
					Assert.fail('should not be invoked');
				}
			});

			delay(1000);
		});

		task.start();

		scheduler.advanceBy(100);

		task.cancel();

		scheduler.advanceBy(1);

		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), CancellationException);
	}

	/**
		The cleanup callback must not run if the continuation was resumed normally before the
		task was cancelled, even if the callback is only installed after the cancellation.
	**/
	function test_cleanup_not_called_after_normal_resume() {
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
