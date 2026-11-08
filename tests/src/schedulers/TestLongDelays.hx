package schedulers;

import haxe.Int64;
import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.schedulers.IScheduler;

/**
	Delays that don't fit into an `Int` used to be truncated with `Int64.toInt`, so a delay of
	2^32 + 10 ms fired after 10 ms. A short control event shows that the loop ran long enough
	for the truncated delay to have fired.
**/
class TestLongDelays extends atest.Test {
	static final longDelay = Int64.make(1, 10);

	static function assertLongDelayWaits(scheduler:IScheduler, loopOnce:() -> Void) {
		var longFired = false;
		var controlFired = false;
		final long = scheduler.schedule(longDelay, new FunctionContinuation(Context.empty, (_, _) -> longFired = true));
		scheduler.schedule(50, new FunctionContinuation(Context.empty, (_, _) -> controlFired = true));
		final deadline = haxe.Timer.stamp() + 30;
		while (!controlFired && haxe.Timer.stamp() < deadline) {
			loopOnce();
		}
		Assert.isTrue(controlFired, "the control event never fired");
		Assert.isFalse(longFired, "the long delay fired early");
		long.close();
	}

	#if !js
	function testHaxeTimerScheduler() {
		assertLongDelayWaits(new hxcoro.schedulers.HaxeTimerScheduler(), () -> haxe.EventLoop.current.loopOnce());
	}
	#end

	#if (cpp && hxcpp_luv_io)
	function testLuvScheduler() {
		final loop = cpp.luv.Luv.allocLoop();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		assertLongDelayWaits(scheduler, () -> scheduler.loop(Once));
		scheduler.shutDown();
		cpp.luv.Luv.shutdownLoop(loop);
		cpp.luv.Luv.freeLoop(loop);
	}
	#end

	#if eval
	function testLuvScheduler() {
		final loop = eval.luv.Loop.init().resolve();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		assertLongDelayWaits(scheduler, () -> scheduler.loop(Once));
		scheduler.shutdown();
		scheduler.loop(NoWait);
	}
	#end
}
