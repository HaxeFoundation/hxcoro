package cases;

import haxe.exceptions.CancellationException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.run.LoopRun;
import hxcoro.run.Setup;
import hxcoro.task.NodeLambda;
import hxcoro.thread.BlockingPool;
import hxcoro.thread.ThreadPoolException;
import sys.thread.Lock;
import sys.thread.Thread;

class TestBlocking extends atest.Test {
	static final setups:Array<() -> LoopSetup> = [Setup.createTrampoline, () -> Setup.createThreadPool(4)];

	static function runWith<T>(createSetup:() -> LoopSetup, lambda:NodeLambda<T>):T {
		final setup = createSetup();
		final task = LoopRun.runTask(setup.loop, setup.createContext(), lambda);
		setup.close();
		return switch (task.getError()) {
			case null: task.get();
			case error: throw error;
		}
	}

	/**
		A `TrampolineDispatcher` runs what is dispatched to it on the dispatching thread, so the
		blocking pool must not resume the caller through it.
	**/
	function testTrampolineCallerResumesOnLoopThread() {
		final loopThread = Thread.current();
		var blockingThread = null;
		var resumedThread = null;
		runWith(Setup.createTrampoline, _ -> {
			blocking(() -> blockingThread = Thread.current());
			resumedThread = Thread.current();
		});
		Assert.isTrue(blockingThread != loopThread, "the function ran on the loop thread");
		Assert.isTrue(resumedThread == loopThread, "the caller was not resumed on the loop thread");
	}

	function testOtherCoroutinesRunDuringCall() {
		for (createSetup in setups) {
			final lock = new Lock();
			final released = runWith(createSetup, node -> {
				final task = node.async(_ -> blocking(() -> lock.wait(5.0)));
				// With a blocked dispatcher, this would not run before the wait timed out.
				lock.release();
				task.await();
			});
			Assert.isTrue(released, "the dispatcher was blocked during the call");
		}
	}

	function testCancelledCallerWaitsForFunction() {
		for (createSetup in setups) {
			final started = new Lock();
			final gate = new Lock();
			var finished = false;
			var finishedWhenResumed = false;
			var cancelled = false;
			runWith(createSetup, node -> {
				final task = node.async(_ -> {
					try {
						blocking(() -> {
							started.release();
							gate.wait(5.0);
							finished = true;
						});
					} catch (e:CancellationException) {
						finishedWhenResumed = finished;
						throw e;
					}
				});
				Assert.isTrue(blocking(() -> started.wait(5.0)), "the function did not start");
				task.cancel();
				yield();
				gate.release();
				try {
					task.await();
				} catch (e:CancellationException) {
					cancelled = true;
				}
			});
			Assert.isTrue(cancelled, "the call did not throw a CancellationException");
			Assert.isTrue(finishedWhenResumed, "the caller was resumed before the function returned");
		}
	}

	function testFunctionOfCancelledCallerIsNotStarted() {
		for (createSetup in setups) {
			final pool = new BlockingPool(1);
			final started = new Lock();
			final gate = new Lock();
			var ran = false;
			var cancelled = false;
			runWith(createSetup, node -> {
				final context = node.with(pool);
				// Occupies the only thread, so that the second call stays queued.
				final first = context.async(_ -> blocking(() -> {
					started.release();
					gate.wait(5.0);
				}));
				Assert.isTrue(blocking(() -> started.wait(5.0)), "the first function did not start");
				final latch = new CoroLatch(1);
				final second = context.async(_ -> {
					latch.arrive(1);
					blocking(() -> ran = true);
				});
				latch.wait();
				second.cancel();
				gate.release();
				try {
					second.await();
				} catch (e:CancellationException) {
					cancelled = true;
				}
				first.await();
			});
			pool.shutDown();
			Assert.isTrue(cancelled, "the call did not throw a CancellationException");
			Assert.isFalse(ran, "the function of a cancelled caller was called");
		}
	}

	function testManyCallsOnSmallPool() {
		for (createSetup in setups) {
			final pool = new BlockingPool(2);
			final sum = runWith(createSetup, node -> {
				final context = node.with(pool);
				final tasks = [for (i in 0...50) context.async(_ -> blocking(() -> {
					Sys.sleep(0.001);
					i;
				}))];
				var sum = 0;
				for (task in tasks) {
					sum += task.await();
				}
				sum;
			});
			pool.shutDown();
			Assert.equals(1225, sum);
		}
	}

	function testClosedSetupRejectsCalls() {
		final setup = Setup.createTrampoline();
		setup.close();
		Assert.raises(() -> setup.blockingPool.run(new NoOp()), ThreadPoolException);
	}
}

private class NoOp implements haxe.coro.dispatchers.IDispatchObject {
	public function new() {}

	public function onDispatch() {}
}
