package features;

import hxcoro.elements.CoroName;

class TestWithout extends utest.Test {
	function test() {
		var outerElement = null;
		var innerElement = new CoroName("foo");
		CoroRun.run(node -> {
			node.with(new CoroName("foo")).async(node -> {
				outerElement = node.context.get(CoroName);
				node.without(CoroName).async(node -> {
					innerElement = node.context.get(CoroName);
				});
			});
		});
		Assert.equals("foo", outerElement.name);
		Assert.isNull(innerElement);
	}
}