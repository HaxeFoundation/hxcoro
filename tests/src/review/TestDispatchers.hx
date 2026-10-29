package review;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
	Known failures from the 1.0 review: dispatchers.
**/
class TestDispatchers extends atest.Test {
	/**
		If a dispatched object throws, `TrampolineDispatcher` never resets `running` for that
		thread. Every later dispatch on the thread is queued and never runs.
	**/
	function testTrampolineRecoversFromThrowingObject() {
		final dispatcher = new TrampolineDispatcher(new VirtualTimeScheduler());
		try {
			dispatcher.dispatchFunction(() -> throw new haxe.Exception("boom"));
		} catch (_:Dynamic) {}
		var ran = false;
		dispatcher.dispatchFunction(() -> ran = true);
		Assert.isTrue(ran, "the trampoline stopped running dispatched objects after one threw");
	}
}
