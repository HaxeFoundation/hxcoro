import sys.FileSystem;
import sys.io.File;

class TestTaskTrace extends atest.Test {
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
