package review;

#if target.threaded
import haxe.atomic.AtomicInt;
import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.schedulers.ThreadAwareScheduler;
import hxcoro.thread.FixedThreadPool;
import sys.thread.Lock;
import sys.thread.Thread;

private class Increment implements IDispatchObject {
	final counter:AtomicInt;

	public function new(counter:AtomicInt) {
		this.counter = counter;
	}

	public function onDispatch() {
		counter.add(1);
	}
}
#end

/**
	Known failures from the 1.0 review that need real threads.

	These avoid open-ended waits. Each wait has a deadline, so a failure costs a few seconds
	rather than hanging the run.
**/
class TestThreading extends atest.Test {
	#if target.threaded
	/**
		The constructor of `FixedThreadPool` installs the shared main queue as the constructing
		thread's own queue, so that thread adds to it without the mutex that all other non-pool
		threads take. The queue supports only one producer, so dispatches from the two threads
		race, and some are lost. In `Setup.createThreadPool` the constructing thread is the one
		that runs the scheduler loop, so every timer firing takes the unlocked path.

		This is a stress test. On eval a single round loses dispatches most of the time, so the
		test runs up to five rounds and stops at the first loss.
	**/
	function testMainQueueAcceptsDispatchesFromTwoForeignThreads() {
		final n = 50000;
		for (round in 0...5) {
			final pool = new FixedThreadPool(4);
			final counter = new AtomicInt(0);
			final otherDone = new Lock();
			Thread.create(() -> {
				for (_ in 0...n) {
					pool.run(new Increment(counter));
				}
				otherDone.release();
			});
			for (_ in 0...n) {
				pool.run(new Increment(counter));
			}
			otherDone.wait(10.0);
			final deadline = Sys.time() + 2.0;
			while (counter.load() < 2 * n && Sys.time() < deadline) {
				Sys.sleep(0.01);
			}
			pool.shutDown(true);
			final executed = counter.load();
			if (executed != 2 * n) {
				Assert.fail('round $round: only $executed of ${2 * n} dispatches were executed');
				return;
			}
		}
		Assert.pass();
	}

	/**
		When a thread exits, `ThreadAwareScheduler` queues the removal of its event queue.
		`loopNoWait` processes that removal before it drains the thread queues, so events that
		the thread scheduled shortly before exiting are lost.
	**/
	function testEventsFromExitedThreadAreDispatched() {
		final scheduler = new ThreadAwareScheduler();
		var fired = false;
		final exited = new Lock();
		Thread.create(() -> {
			scheduler.schedule(0, new FunctionContinuation(Context.empty, (_, _) -> fired = true));
			Thread.addCurrentCallbacks({onExit: () -> exited.release()});
		});
		Assert.isTrue(exited.wait(5.0), "the thread did not exit");
		// Give the remaining exit callbacks of the thread time to run.
		Sys.sleep(0.05);
		scheduler.loop(NoWait);
		Assert.isTrue(fired, "the event scheduled by the exited thread was dropped");
	}
	#else
	function testNotThreaded() {
		Assert.pass();
	}
	#end
}
