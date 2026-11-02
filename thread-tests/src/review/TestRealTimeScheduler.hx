package review;

import hxcoro.run.LoopRun;
import hxcoro.run.Setup;
import sys.thread.Lock;
import sys.thread.Thread;

/**
	Known failures from the 1.0 review: `RealTimeScheduler`.
**/
class TestRealTimeScheduler extends atest.Test {
	/**
		P4: `RealTimeScheduler.loop(Once)` ignores `wakeUp`, so the loop spins forever.

		`src/hxcoro/schedulers/RealTimeScheduler.hx:36-50`: `Once` busy-waits until an event is
		dispatched, and `wakeUp()` is a no-op. `LoopRun.awaitTaskCompletion` (`run/LoopRun.hx:40-56`)
		relies on `wakeUp` from `onCompletion`. Here the task is resumed from a foreign thread, where
		the `TrampolineDispatcher` runs it inline, so it completes without dispatching anything to
		the loop, and the loop spins at 100% CPU forever. This setup is the default on hl, python and
		neko (`Setup.createDefault`). `Once` with a long `delay` also burns a core.

		Fix: an atomic wake flag set by `wakeUp` and checked in the spin. Better: block on a
		`sys.thread.Semaphore`/`Condition` with a timeout until the earliest due time, as
		`ThreadAwareScheduler` does (reuse its `WakeUpFlag` approach). Keep a pure spin only on
		non-threaded targets.
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
}
