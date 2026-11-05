package structured;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
	A dispatcher that only queues what is dispatched to it, until `runAll` is called, and counts
	the dispatches.
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
	A task runs on the dispatcher of its context, even if it is started from a task on another
	dispatcher, and it is dispatched only once, however often its start is requested.
**/
class TestStartDispatcher extends atest.Test {
	function testAwaitDoesNotStartTaskInline() {
		final scheduler = new VirtualTimeScheduler();
		final manual = new ManualDispatcher(scheduler);
		final events = [];
		final task = CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			final child = node.with(manual).async(_ -> {
				events.push("child runs");
				42;
			});
			events.push("awaiting");
			events.push("result " + child.await());
		});
		Assert.same(["awaiting"], events);
		// `async` dispatched the child, and `await` must not dispatch it again.
		Assert.equals(1, manual.dispatched);
		manual.runAll();
		Assert.same(["awaiting", "child runs", "result 42"], events);
		Assert.isFalse(task.isActive());
	}

	function testExplicitStartFromOtherDispatcher() {
		final scheduler = new VirtualTimeScheduler();
		final manual = new ManualDispatcher(scheduler);
		final events = [];
		CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			final child = node.with(manual).lazy(_ -> {
				events.push("child runs");
			});
			child.start(node);
			events.push("started");
		});
		Assert.same(["started"], events);
		// The parent's own work has finished too, which must not dispatch the started child again.
		Assert.equals(1, manual.dispatched);
		manual.runAll();
		Assert.same(["started", "child runs"], events);
	}

	function testStartTwiceDispatchesOnce() {
		final scheduler = new VirtualTimeScheduler();
		final manual = new ManualDispatcher(scheduler);
		var runs = 0;
		CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			final child = node.with(manual).lazy(_ -> {
				runs++;
			});
			child.start(node);
			child.start(node);
		});
		Assert.equals(1, manual.dispatched);
		manual.runAll();
		Assert.equals(1, runs);
	}

	function testLazyChildStartsOnItsDispatcher() {
		final scheduler = new VirtualTimeScheduler();
		final manual = new ManualDispatcher(scheduler);
		final events = [];
		CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			node.with(manual).lazy(_ -> {
				events.push("child runs");
			});
			events.push("parent done");
		});
		// The parent's own work has finished, which starts the lazy child, but on its dispatcher.
		Assert.same(["parent done"], events);
		Assert.equals(1, manual.dispatched);
		manual.runAll();
		Assert.same(["parent done", "child runs"], events);
	}

	function testScopeRunsInline() {
		final scheduler = new VirtualTimeScheduler();
		final events = [];
		CoroRun.with(new TrampolineDispatcher(scheduler)).launchTask(node -> {
			node.async(_ -> {
				events.push("sibling");
			});
			scope(_ -> {
				events.push("scope");
			});
		});
		// The scope runs on the same dispatcher as its caller, so it doesn't queue behind the sibling.
		Assert.same(["scope", "sibling"], events);
	}
}
