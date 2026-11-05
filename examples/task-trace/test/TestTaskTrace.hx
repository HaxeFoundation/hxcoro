import hxcoro.Coro.*;
import hxcoro.CoroRun;
import hxcoro.debug.TaskTrace;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import sys.FileSystem;
import sys.io.File;

using hxcoro.util.Convenience;

class TestTaskTrace extends atest.Test {
	/**
		Only the tasks created in a context with the element are traced, including their descendants.
	**/
	function testOnlyTasksInTheTracedContextAreTraced() {
		final events = [];
		final trace = new TaskTrace(event -> events.push(event));
		var tracedId = 0;
		var grandchildId = 0;
		var siblingId = 0;
		final scheduler = new VirtualTimeScheduler();
		final root = CoroRun.with(new TrampolineDispatcher(scheduler)).createTask(node -> {
			siblingId = node.async(_ -> yield()).id;
			tracedId = node.with(trace).async(t -> {
				grandchildId = t.async(_ -> yield()).id;
				yield();
			}).id;
		});
		root.start();
		while (root.isActive()) {
			scheduler.advanceBy(1);
		}
		Assert.isFalse(root.isFailed());
		final tracedTasks = new Map<Int, Bool>();
		for (event in events) {
			tracedTasks.set(event.task.id, true);
		}
		final expected = [tracedId, grandchildId];
		expected.sort(Reflect.compare);
		final actual = [for (id in tracedTasks.keys()) id];
		actual.sort(Reflect.compare);
		Assert.same(expected, actual);
	}

	function testEveryScenarioIsTraced() {
		for (scenario in Scenarios.all) {
			final events = Scenarios.record(scenario);
			Assert.isTrue(events.length > 0, '${scenario.title} produced no events');
			Assert.isTrue(events.filter(e -> e.method == "state").length > 0, '${scenario.title} produced no state changes');
		}
	}

	/**
		`diagrams.md` is committed, so the diagrams are visible on GitHub and stay current: this
		regenerates it and fails if it was out of date.
	**/
	function testDiagramsAreUpToDate() {
		final path = "diagrams.md";
		final markdown = Scenarios.renderAll();
		final current = FileSystem.exists(path) ? StringTools.replace(File.getContent(path), "\r\n", "\n") : null;
		if (current == markdown) {
			Assert.isTrue(true);
			return;
		}
		File.saveContent(path, markdown);
		Assert.fail("diagrams.md was out of date and has been regenerated, commit it");
	}
}
