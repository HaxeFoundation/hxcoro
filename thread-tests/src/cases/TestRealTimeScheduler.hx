package cases;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.run.LoopRun;
import hxcoro.run.Setup;
import hxcoro.schedulers.RealTimeScheduler;
import sys.thread.Lock;
import sys.thread.Thread;

/**
	The loops run on separate threads, so a `loop(Once)` that never returns fails the test after a
	deadline instead of blocking the test run.
**/
class TestRealTimeScheduler extends atest.Test {
	/**
		A task resumed from another thread completes there, because the `TrampolineDispatcher` runs
		it inline, without dispatching anything to the loop. `LoopRun` calls `wakeUp` for this, which
		`RealTimeScheduler` used to ignore, so the loop spun forever.
	**/
	function testTaskCompletedFromForeignThread() {
		final done = new Lock();
		var result = 0;
		Thread.create(() -> {
			final setup = Setup.createTrampoline();
			final task = LoopRun.runTask(setup.loop, setup.createContext(), _ -> {
				return suspend(cont -> {
					Thread.create(() -> {
						// Resume after the coroutine has suspended.
						Sys.sleep(0.05);
						cont.resume(1, null);
					});
				});
			});
			setup.close();
			result = task.get();
			done.release();
		});
		Assert.isTrue(done.wait(5.0), "the loop never noticed that the task completed");
		Assert.equals(1, result);
	}

	/**
		While `loop(Once)` waits for an event that is due later, an event scheduled from another
		thread that is due now must be dispatched without waiting for the later one.
	**/
	function testEarlierEventFromOtherThreadIsDispatched() {
		final scheduler = new RealTimeScheduler();
		scheduler.schedule(60000, new FunctionContinuation(Context.empty, (_, _) -> {}));
		final returned = new Lock();
		var fired = false;
		Thread.create(() -> {
			scheduler.loop(Once);
			returned.release();
		});
		Sys.sleep(0.05);
		scheduler.schedule(0, new FunctionContinuation(Context.empty, (_, _) -> fired = true));
		Assert.isTrue(returned.wait(5.0), "loop(Once) kept waiting for the later event");
		Assert.isTrue(fired);
	}

	/**
		A `wakeUp` that happens before `loop(Once)` runs must not get lost. Once a `loop(Once)` call
		has returned because of it, the next one waits again.
	**/
	function testWakeUpBeforeOnceIsNotLost() {
		final scheduler = new RealTimeScheduler();
		final returned = new Lock();
		final scheduled = new Lock();
		var fired = false;
		var firedAfterSecondLoop = false;
		Thread.create(() -> {
			scheduler.wakeUp();
			scheduler.loop(Once);
			returned.release();
			// The wake-up was used up, so this has to wait for the event.
			scheduler.loop(Once);
			firedAfterSecondLoop = fired;
			scheduled.release();
		});
		Assert.isTrue(returned.wait(5.0), "loop(Once) did not return after wakeUp");
		Sys.sleep(0.05);
		scheduler.schedule(0, new FunctionContinuation(Context.empty, (_, _) -> fired = true));
		Assert.isTrue(scheduled.wait(5.0), "loop(Once) did not dispatch the event");
		Assert.isTrue(firedAfterSecondLoop, "loop(Once) returned before the event was scheduled");
	}

	function testWakeUpFromOtherThread() {
		final scheduler = new RealTimeScheduler();
		final returned = new Lock();
		Thread.create(() -> {
			scheduler.loop(Once);
			returned.release();
		});
		Sys.sleep(0.05);
		scheduler.wakeUp();
		Assert.isTrue(returned.wait(5.0), "loop(Once) did not return after wakeUp");
	}

	function testOnceWaitsForDueEvent() {
		final scheduler = new RealTimeScheduler();
		var fired = false;
		scheduler.schedule(50, new FunctionContinuation(Context.empty, (_, _) -> fired = true));
		final returned = new Lock();
		Thread.create(() -> {
			scheduler.loop(Once);
			returned.release();
		});
		Assert.isTrue(returned.wait(5.0), "loop(Once) did not return once the event was due");
		Assert.isTrue(fired);
	}
}
