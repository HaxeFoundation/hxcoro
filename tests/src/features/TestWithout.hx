package features;

import hxcoro.components.CoroName;

class TestWithout extends utest.Test {
	function test() {
		var outerComponent = null;
		var innerComponent = new CoroName("foo");
		CoroRun.runScoped(node -> {
			node.with(new CoroName("foo")).async(node -> {
				outerComponent = node.context.get(CoroName);
				node.without(CoroName).async(node -> {
					innerComponent = node.context.get(CoroName);
				});
			});
		});
		Assert.equals("foo", outerComponent.name);
		Assert.isNull(innerComponent);
	}
}