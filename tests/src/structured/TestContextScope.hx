package structured;

import haxe.Exception;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.exceptions.CancellationException;
import hxcoro.TimeoutException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.elements.CoroName;
import hxcoro.elements.NonCancellable;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;

/**
	A dispatcher that only queues what is dispatched to it, until `runAll` is called.
**/
private class ManualDispatcher extends Dispatcher {
	final s:IScheduler;
	final queue:Array<IDispatchObject>;

	public var dispatched(default, null):Int;

	public function new(scheduler:IScheduler) {
		s = scheduler;
		queue = [];
		dispatched = 0;
	}

	function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IDispatchObject) {
		dispatched++;
		queue.push(obj);
	}

	public function runAll() {
		var obj = null;
		while ((obj = queue.shift()) != null) {
			obj.onDispatch();
		}
	}
}

/**
	`context.scope` runs a block in a child task created with that context.
**/
class TestContextScope extends atest.Test {
	function testElementIsVisibleAndResultIsReturned() {
		final name = new CoroName("inner");
		var seen:Null<CoroName> = null;
		var result = 0;
		final task = VirtualRun.run(node -> {
			result = node.with(name).scope(n -> {
				seen = n.context.get(CoroName);
				42;
			});
		});
		Assert.isFalse(task.isActive());
		Assert.equals(42, result);
		Assert.isTrue(seen == name, "the block didn't see the element");
	}

	function testExceptionIsThrownAtCallSite() {
		var caught:Null<Exception> = null;
		var continued = false;
		final task = VirtualRun.run(node -> {
			try {
				node.with(new CoroName("x")).scope(_ -> throw new Exception("boom"));
			} catch (e:Exception) {
				caught = e;
			}
			continued = true;
		});
		Assert.isFalse(task.isActive());
		Assert.isNull(task.getError(), "the caller failed although it caught the exception");
		Assert.isTrue(continued);
		Assert.equals("boom", caught?.message);
	}

	function testRunsInlineOnSameDispatcher() {
		final scheduler = new VirtualTimeScheduler();
		final events = [];
		CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			node.async(_ -> {
				events.push("sibling");
			});
			node.with(new CoroName("x")).scope(_ -> {
				events.push("scope");
			});
		});
		Assert.same(["scope", "sibling"], events);
	}

	function testRunsOnOtherDispatcher() {
		final scheduler = new VirtualTimeScheduler();
		final manual = new ManualDispatcher(scheduler);
		final events = [];
		final task = CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			events.push("before");
			node.with(manual).scope(_ -> {
				events.push("scope");
			});
			events.push("after");
		});
		Assert.same(["before"], events);
		Assert.equals(1, manual.dispatched, "the block was dispatched more than once");
		manual.runAll();
		Assert.same(["before", "scope", "after"], events);
		Assert.equals(1, manual.dispatched);
		Assert.isFalse(task.isActive());
	}

	function testContextWithoutTaskRunsDetached() {
		var result = 0;
		var blockCancelled = false;
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			t = node.async(n -> {
				result = n.without(CoroBaseTask.key).scope(_ -> {
					try {
						latch.wait();
					} catch (e:CancellationException) {
						blockCancelled = true;
						throw e;
					}
					42;
				});
			});
			yield();
			t.cancel();
			yield();
			latch.arrive(1);
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(t.isCancelled());
		Assert.isFalse(blockCancelled, "cancelling the caller cancelled a block without a parent");
		Assert.equals(42, result);
	}

	function testNonCancellableCleanupCompletes() {
		var cleanupRan = false;
		var cause:Null<CancellationException> = null;
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			t = node.async(n -> {
				try {
					awaitCancellation();
				} catch (e:CancellationException) {
					cause = e;
					n.with(new NonCancellable()).scope(_ -> {
						delay(10);
						cleanupRan = true;
					});
					throw e;
				}
			});
			yield();
			t.cancel();
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(cleanupRan, "the NonCancellable block didn't run to completion");
		Assert.isTrue(t.isCancelled());
		Assert.isTrue(t.getError() == cause, "the task's cause changed");
	}

	function testTimeoutInsideNonCancellableBlock() {
		var timedOut = false;
		final task = VirtualRun.run(node -> {
			node.with(new NonCancellable()).scope(_ -> {
				try {
					timeout(10, _ -> delay(100));
				} catch (_:TimeoutException) {
					timedOut = true;
				}
			});
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(timedOut, "timeout inside the block didn't fire");
	}

	function testCallerCancellationCancelsBlock() {
		var blockCancelled = false;
		var t:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			t = node.async(n -> {
				n.with(new CoroName("x")).scope(_ -> {
					try {
						awaitCancellation();
					} catch (e:CancellationException) {
						blockCancelled = true;
						throw e;
					}
				});
			});
			yield();
			t.cancel();
		});
		Assert.isFalse(task.isActive(), "the run never completed");
		Assert.isTrue(blockCancelled, "the block was not cancelled with its caller");
		Assert.isTrue(t.isCancelled());
	}
}
