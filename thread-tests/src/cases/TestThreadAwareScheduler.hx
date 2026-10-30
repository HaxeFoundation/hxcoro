package cases;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.run.LoopRun;
import hxcoro.run.Setup;
import hxcoro.schedulers.ThreadAwareScheduler;
import sys.thread.Lock;
import sys.thread.Thread;

class TestThreadAwareScheduler extends atest.Test {
	/**
		When a thread exits, `ThreadAwareScheduler` queues the removal of its event queue. The
		events that the thread scheduled shortly before exiting must still be dispatched.
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

	// Not on neko: assigning a declared field for the first time adds it to the object, which is
	// not safe while another thread reads the object. The thread pool shares continuations
	// between threads like that, so this test fails there for reasons unrelated to the scheduler.
	// See https://github.com/HaxeFoundation/neko/issues/335
	#if !neko
	/**
		Pool threads schedule their `yield` resumptions into their own queues, which the loop
		thread drains. The queue's indices used to be plain fields, so the loop thread could see
		an advanced write index before the event itself, and lose the event. The run then hung.
		On the JVM, this happened within a few rounds.

		The rounds run on a separate thread, so a hang fails the test after a deadline instead
		of blocking the test run.
	**/
	function testYieldBurstsOnThreadPool() {
		final rounds = #if (jvm || cpp) 100 #else 2 #end;
		final yieldsPerTask = #if (jvm || cpp) 2000 #else 200 #end;
		final done = new Lock();
		Thread.create(() -> {
			for (_ in 0...rounds) {
				final setup = Setup.createThreadPool(4);
				LoopRun.runTask(setup.loop, setup.createContext(), node -> {
					for (_ in 0...32) {
						node.async(_ -> {
							for (_ in 0...yieldsPerTask) {
								yield();
							}
						});
					}
				});
				setup.close();
			}
			done.release();
		});
		Assert.isTrue(done.wait(60.0), "the run hung, so an event was lost");
	}
	#end
}
