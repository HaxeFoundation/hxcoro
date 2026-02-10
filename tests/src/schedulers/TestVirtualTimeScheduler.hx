package schedulers;

import hxcoro.dispatchers.SelfDispatcher;
import haxe.coro.context.Context;
import haxe.Int64;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.exceptions.ArgumentException;

using TestVirtualTimeScheduler.VirtualTimeSchedulerTools;

class VirtualTimeSchedulerTools {
	static public function scheduleFunction<T>(sut:VirtualTimeScheduler, ms:Int64, func:() -> T) {
		return (Context.create(new SelfDispatcher(sut)) : Context).scheduleFunction(ms, func);
	}
}

class TestVirtualTimeScheduler extends utest.Test {
	public function test_time_after_advancing_by() {
		final sut = new VirtualTimeScheduler();

		Assert.isTrue(0i64 == sut.now());

		sut.advanceBy(100);
		Assert.isTrue(100i64 == sut.now());

		sut.advanceBy(400);
		Assert.isTrue(500i64 == sut.now());
	}

	public function test_time_after_advancing_to() {
		final sut = new VirtualTimeScheduler();

		Assert.isTrue(0i64 == sut.now());

		sut.advanceTo(100);
		Assert.isTrue(100i64 == sut.now());

		sut.advanceTo(400);
		Assert.isTrue(400i64 == sut.now());
	}

	public function test_scheduling_immediate_function() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(0, () -> result.push(0));
		sut.loop(NoWait);

		Assert.same([ 0 ], result);
	}

	public function test_scheduling_future_function() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(10, () -> result.push(0));
		sut.advanceBy(10);

		Assert.same([ 0 ], result);
	}

	public function test_scheduling_multiple_future_function_same_time() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(10, () -> result.push(0));
		sut.scheduleFunction(10, () -> result.push(1));
		sut.advanceBy(10);

		Assert.same([ 0, 1 ], result);
	}

	public function test_scheduling_all_functions_up_to_time() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(10, () -> result.push(0));
		sut.scheduleFunction(20, () -> result.push(1));
		sut.advanceBy(20);

		Assert.same([ 0, 1 ], result);
	}

	public function test_scheduling_functions_at_their_due_time() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(10, () -> result.push(sut.now()));
		sut.scheduleFunction(20, () -> result.push(sut.now()));
		sut.advanceBy(20);

		Assert.isTrue(10i64 == result[0]);
		Assert.isTrue(20i64 == result[1]);
	}

	public function test_scheduling_recursive_immediate_functions() {
		final result = [];
		final sut    = new VirtualTimeScheduler();

		sut.scheduleFunction(0, () -> {
			result.push(0);

			sut.scheduleFunction(0, () -> {
				result.push(1);

				sut.scheduleFunction(0, () -> {
					result.push(2);
				});
				sut.loop(NoWait);
			});
			sut.loop(NoWait);
		});
		sut.loop(NoWait);

		Assert.same([ 0, 1, 2 ], result);
	}

	public function test_scheduling_negative_time() {
		final sut = new VirtualTimeScheduler();

		Assert.raises(() -> sut.scheduleFunction(-1, () -> {}), ArgumentException);
	}

	public function test_advancing_by_negative_time() {
		final sut = new VirtualTimeScheduler();

		Assert.raises(() -> sut.advanceBy(-1), ArgumentException);
	}

	public function test_advancing_to_the_past() {
		final sut = new VirtualTimeScheduler();

		sut.advanceTo(1000);

		Assert.raises(() -> sut.advanceTo(500), ArgumentException);
	}

	public function test_cancelling_scheduled_event() {
		final result = [];
		final sut    = new VirtualTimeScheduler();
		final _      = sut.scheduleFunction(10, () -> result.push(0));
		final handle = sut.scheduleFunction(20, () -> result.push(1));
		final _      = sut.scheduleFunction(30, () -> result.push(2));

		handle.close();

		sut.advanceTo(30);

		Assert.same([ 0, 2 ], result);
	}

	public function test_cancelling_head() {
		final result = [];
		final sut    = new VirtualTimeScheduler();
		final handle = sut.scheduleFunction(10, () -> result.push(0));
		final _      = sut.scheduleFunction(20, () -> result.push(1));

		handle.close();

		sut.advanceTo(20);

		Assert.same([ 1 ], result);
	}

	public function test_cancelling_single_head() {
		final result = [];
		final sut    = new VirtualTimeScheduler();
		final handle = sut.scheduleFunction(10, () -> result.push(0));

		handle.close();

		sut.advanceTo(10);

		Assert.same([], result);
	}

	public function test_cancelling_executed_function() {
		final result = [];
		final sut    = new VirtualTimeScheduler();
		final handle = sut.scheduleFunction(10, () -> result.push(0));

		sut.advanceTo(10);

		handle.close();

		Assert.same([ 0 ], result);
	}
}