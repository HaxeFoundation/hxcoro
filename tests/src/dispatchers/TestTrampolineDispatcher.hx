package dispatchers;

import haxe.Exception;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;

class TestTrampolineDispatcher extends atest.Test {
	/**
		An exception from a dispatched object reaches the caller of `dispatch`.
	**/
	function testExceptionPropagatesToCaller() {
		final dispatcher = new TrampolineDispatcher(new VirtualTimeScheduler());
		var caught:Null<Exception> = null;
		try {
			dispatcher.dispatchFunction(() -> throw new Exception("boom"));
		} catch (e:Exception) {
			caught = e;
		}
		Assert.equals("boom", caught?.message);
	}

	/**
		After a dispatched object threw, the trampoline must still run later dispatches on the
		same thread. It used to stay marked as running and queue them forever.
	**/
	function testRecoversFromThrowingObject() {
		final dispatcher = new TrampolineDispatcher(new VirtualTimeScheduler());
		try {
			dispatcher.dispatchFunction(() -> throw new Exception("boom"));
		} catch (_:Exception) {}
		var ran = false;
		dispatcher.dispatchFunction(() -> ran = true);
		Assert.isTrue(ran, "the trampoline stopped running dispatched objects after one threw");
	}

	/**
		Objects that were queued behind a throwing one stay queued, and run before the object of
		the next dispatch on the same thread.
	**/
	function testQueuedObjectsRunFirstAfterException() {
		final dispatcher = new TrampolineDispatcher(new VirtualTimeScheduler());
		final order = [];
		try {
			dispatcher.dispatchFunction(() -> {
				dispatcher.dispatchFunction(() -> order.push("queued 1"));
				dispatcher.dispatchFunction(() -> order.push("queued 2"));
				throw new Exception("boom");
			});
		} catch (_:Exception) {}
		Assert.same([], order, "queued objects ran before the exception reached the caller");
		dispatcher.dispatchFunction(() -> order.push("next"));
		Assert.same(["queued 1", "queued 2", "next"], order);
	}

	/**
		If an object that was queued behind the first one throws, the objects after it stay
		queued as well.
	**/
	function testExceptionWhileDrainingQueue() {
		final dispatcher = new TrampolineDispatcher(new VirtualTimeScheduler());
		final order = [];
		var caught:Null<Exception> = null;
		try {
			dispatcher.dispatchFunction(() -> {
				dispatcher.dispatchFunction(() -> throw new Exception("queued failure"));
				dispatcher.dispatchFunction(() -> order.push("queued"));
			});
		} catch (e:Exception) {
			caught = e;
		}
		Assert.equals("queued failure", caught?.message);
		dispatcher.dispatchFunction(() -> order.push("next"));
		Assert.same(["queued", "next"], order);
	}
}
