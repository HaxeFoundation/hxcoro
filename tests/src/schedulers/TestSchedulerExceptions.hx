package schedulers;

import haxe.Exception;
import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.schedulers.IScheduler;
import hxcoro.schedulers.ILoop;
import hxcoro.schedulers.RealTimeScheduler;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
	If dispatching a scheduled event throws, the exception propagates right away, but the other
	events that were due must not be lost. Events with the same due time are merged in the heap,
	so they used to be dropped together with the throwing one.

	The continuations here have no dispatcher, so they run immediately and their exceptions
	escape from the scheduler, as they do with a `TrampolineDispatcher`.
**/
class TestSchedulerExceptions extends atest.Test {
	static function scheduleAll(scheduler:IScheduler, ms:Int, log:Array<String>) {
		scheduler.schedule(ms, new FunctionContinuation(Context.empty, (_, _) -> throw new Exception("boom")));
		scheduler.schedule(ms, new FunctionContinuation(Context.empty, (_, _) -> log.push("second")));
		scheduler.schedule(ms, new FunctionContinuation(Context.empty, (_, _) -> log.push("third")));
	}

	static function loopCatching(loop:() -> Void) {
		try {
			loop();
		} catch (e:Exception) {
			return e.message;
		}
		return null;
	}

	function testVirtualTimeSchedulerKeepsSiblingEvents() {
		final scheduler = new VirtualTimeScheduler();
		final log = [];
		scheduleAll(scheduler, 10, log);
		Assert.equals("boom", loopCatching(() -> scheduler.advanceBy(10)));
		scheduler.advanceBy(0);
		Assert.same(["second", "third"], log);
	}

	function testRealTimeSchedulerKeepsSiblingEvents() {
		final scheduler = new RealTimeScheduler();
		final log = [];
		scheduleAll(scheduler, 0, log);
		Assert.equals("boom", loopCatching(() -> scheduler.loop(NoWait)));
		scheduler.loop(NoWait);
		Assert.same(["second", "third"], log);
	}

	#if target.threaded
	/**
		`ThreadAwareScheduler` collects due events into one list before dispatching them, so a
		throwing event used to lose the rest of that list.
	**/
	function testThreadAwareSchedulerKeepsDueEvents() {
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final log = [];
		scheduleAll(scheduler, 0, log);
		Assert.equals("boom", loopCatching(() -> scheduler.loop(NoWait)));
		scheduler.loop(NoWait);
		log.sort(Reflect.compare);
		Assert.same(["second", "third"], log);
	}
	#end
}
