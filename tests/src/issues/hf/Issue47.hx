package issues.hf;

import hxcoro.components.NonCancellable;
import haxe.exceptions.CancellationException;

class Issue47 extends utest.Test {
	function testTaskActiveAfterCancellation() {
		CoroRun.runScoped(node -> {
			var cancelCause = null;
			final task = node.async(node -> {
				try {
					while (true) {
						yield();
					}
				} catch (e:CancellationException) {
					cancelCause = e;
					throw e;
				}
			});
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			Assert.isTrue(task.isActive());
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testCancellableTaskFromCancelledTask() {
		CoroRun.runScoped(node -> {
			var cancelCause = null;
			final task = node.async(node -> {
				try {
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
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			Assert.isTrue(task.isActive());
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testNonCancellableTaskFromCancelledTask() {
		CoroRun.runScoped(node -> {
			var cancelCause = null;
			final task = node.async(node -> {
				try {
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
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			Assert.isTrue(task.isActive());
			AssertAsync.raises(() -> task.await(), CancellationException);
			Assert.equals(cancelCause, cancelCause2);
			Assert.isFalse(task.isActive());
		});
	}

	function testLazyNonCancellableTaskFromCancelledTask() {
		CoroRun.runScoped(node -> {
			var cancelCause = null;
			final task = node.async(node -> {
				try {
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
			final cancelCause2 = new CancellationException();
			task.cancel(cancelCause2);
			Assert.isTrue(task.isActive());
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
		Assert.raises(() -> {
			CoroRun.runScoped(node -> {
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
		}, String);
		Assert.same(expected, actual);
	}
}