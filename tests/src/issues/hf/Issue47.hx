package issues.hf;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.concurrent.CoroSemaphore;
import hxcoro.elements.NonCancellable;
import haxe.exceptions.CancellationException;

class Issue47 extends utest.Test {
	function testTaskActiveAfterCancellation() {
		CoroRun.run(node -> {
			var cancelCause = null;
			final sem = new CoroSemaphore(0, 1);
			final task = node.async(node -> {
				try {
					sem.release();
					while (true) {
						yield();
					}
				} catch (e:CancellationException) {
					cancelCause = e;
					throw e;
				}
			});
			sem.acquire();
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testCancellableTaskFromCancelledTask() {
		CoroRun.run(node -> {
			var cancelCause = null;
			final sem = new CoroSemaphore(0, 1);
			final task = node.async(node -> {
				try {
					sem.release();
					while (true) {
						yield();
					}
				} catch (e:CancellationException) {
					node.async(node -> {
						cancelCause = e;
						yield();
						throw "Should not be reached";
					});
					throw e;
				}
			});
			sem.acquire();
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, null);
			Assert.isFalse(task.isActive());
		});
	}

	function testNonCancellableTaskFromCancelledTask() {
		CoroRun.run(node -> {
			var cancelCause = null;
			final sem = new CoroSemaphore(0, 1);
			final task = node.async(node -> {
				try {
					sem.release();
					while (true) {
						yield();
					}
				} catch (e:CancellationException) {
					node.with(new NonCancellable()).async(node -> {
						yield();
						cancelCause = e;
					});
					throw e;
				}
			});
			sem.acquire();
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testLazyNonCancellableTaskFromCancelledTask() {
		CoroRun.run(node -> {
			var cancelCause = null;
			final sem = new CoroSemaphore(0, 1);
			final task = node.async(node -> {
				try {
					sem.release();
					while (true) {
						yield();
					}
				} catch (e:CancellationException) {
					final task = node.with(new NonCancellable()).lazy(node -> {
						yield();
						cancelCause = e;
					});
					task.start();
					throw e;
				}
			});
			sem.acquire();
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testKotlinSample() {
		final expected = [
			"Second child throws an exception",
			"Children are cancelled, but exception is not handled until all children terminate",
			"The first child finished its non cancellable block"
		];
		final actual = [];
		function add(s:String) {
			actual.push(s);
		}
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task = CoroRun.with(dispatcher).createTask(node -> {
			node.async(node -> {
				try {
					delay(10000);
				} catch (e:CancellationException) {
					node.with(new NonCancellable()).async(node -> {
						add(expected[1]);
						delay(100);
						add(expected[2]);
					});
					throw e;
				}
			});
			node.async(node -> {
				delay(10);
				add(expected[0]);
				throw "ArithmeticException";
			});
		});
		task.start();
		scheduler.advanceBy(110);
		Assert.isFalse(task.isActive());
		Assert.notNull(task.getError());
		Assert.same(expected, actual);
	}
}