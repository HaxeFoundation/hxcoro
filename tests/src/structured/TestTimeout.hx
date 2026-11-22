package structured;

import hxcoro.dispatchers.TrampolineDispatcher;
import haxe.Exception;
import haxe.exceptions.ArgumentException;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.TimeoutException;

class TestTimeout extends atest.Test {
	function test_timeout() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			return timeout(500, _ -> {
				delay(1000);

				return 10;
			});
		});

		task.start();

		scheduler.advanceBy(500);

		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), TimeoutException);
	}

	function test_timeout_result() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			return timeout(1000, _ -> {
				delay(500);

				return 10;
			});
		});

		task.start();

		scheduler.advanceBy(500);

		Assert.isFalse(task.isActive());
		Assert.equals(10, task.get());
	}

	#if !hl // TODO: crashes HL with exit code -1; investigate timeout(0,...) with TrampolineDispatcher
	function test_zero_timeout() {
		final result     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			return timeout(0, _ -> {
				result.push(0);
			});
		});

		task.start();

		scheduler.advanceBy(0);

		Assert.isFalse(task.isActive());
		Assert.same([], result);
	}
	#end

	function test_negative_timeout() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			return timeout(-1, _ -> {
				delay(1000);
			});
		});

		task.start();

		scheduler.advanceBy(0);

		Assert.isFalse(task.isActive());
		Assert.isOfType(task.getError(), ArgumentException);
	}

	function test_timeout_does_not_propagate_cancellation() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(node -> {
			node.async(_ -> {
				try {
					timeout(500, _ -> {
						delay(1000);
					});
				} catch (_) {}
			});

			return node.async(_ -> {
				delay(100);

				return 10;
			}).await();
		});

		task.start();

		scheduler.advanceBy(500);

		Assert.isFalse(task.isActive());
		Assert.equals(10, task.get());
	}

	function test_timeoutOr_result() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(1000, () -> -1, _ -> {
				delay(500);
				return 10;
			});
		});
		Assert.equals(10, task.get());
	}

	function test_timeoutOr_fallback() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(500, () -> -1, _ -> {
				delay(1000);
				return 10;
			});
		});
		Assert.equals(-1, task.get());
	}

	function test_timeoutOr_zero() {
		var ran = false;
		final task = VirtualRun.run(_ -> {
			return timeoutOr(0, () -> -1, _ -> {
				ran = true;
				return 10;
			});
		});
		Assert.equals(-1, task.get());
		Assert.isFalse(ran);
	}

	function test_timeoutOr_negative() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(-1, () -> -1, _ -> 10);
		});
		Assert.isOfType(task.getError(), ArgumentException);
	}

	function test_timeoutOr_exception() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(500, () -> -1, _ -> {
				throw new Exception("boom");
			});
		});
		Assert.equals("boom", task.getError().message);
	}

	function test_timeoutOr_fallback_throws() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(500, () -> throw new Exception("no reply"), _ -> {
				delay(1000);
				return 10;
			});
		});
		Assert.equals("no reply", task.getError().message);
	}

	/**
		The expiry of an enclosing time limit is not the inner call's own, so its fallback
		must not run. See https://github.com/HaxeFoundation/hxcoro/issues/259.
	**/
	function test_timeoutOr_enclosing_timeout() {
		var innerFallback = false;
		final task = VirtualRun.run(_ -> {
			return timeoutOr(100, () -> "outer", _ -> {
				return timeoutOr(1000, () -> {
					innerFallback = true;
					"inner";
				}, _ -> {
					delay(3000);
					return "done";
				});
			});
		});
		Assert.equals("outer", task.get());
		Assert.isFalse(innerFallback);
	}

	function test_timeoutOr_enclosing_timeout_throws() {
		var innerFallback = false;
		final task = VirtualRun.run(_ -> {
			return timeout(100, _ -> {
				return timeoutOr(1000, () -> {
					innerFallback = true;
					"inner";
				}, _ -> {
					delay(3000);
					return "done";
				});
			});
		});
		Assert.isOfType(task.getError(), TimeoutException);
		Assert.isFalse(innerFallback);
	}

	function test_timeoutOr_inner_expires_first() {
		final task = VirtualRun.run(_ -> {
			return timeoutOr(1000, () -> "outer", _ -> {
				return timeoutOr(100, () -> "inner", _ -> {
					delay(3000);
					return "done";
				});
			});
		});
		Assert.equals("inner", task.get());
	}

	/**
		A retry loop under an enclosing time limit ends with that limit, instead of handling
		its expiry as the inner one on every iteration.
	**/
	function test_timeoutOr_loop_ends_with_enclosing_timeout() {
		var iterations = 0;
		final task = VirtualRun.run(_ -> {
			return timeoutOr(250, () -> "outer", _ -> {
				while (iterations < 1000) {
					timeoutOr(100, () -> {}, _ -> delay(3000));
					iterations++;
				}
				return "loop ended";
			});
		});
		Assert.equals("outer", task.get());
		Assert.equals(2, iterations);
	}
}
