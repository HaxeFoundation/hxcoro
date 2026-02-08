package structured;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.exceptions.ArgumentException;
import haxe.exceptions.CancellationException;

class TestCancellingSuspend extends utest.Test {
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
}
