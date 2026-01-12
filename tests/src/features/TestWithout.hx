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

	function testLocal() {
		final actual = [];
		CoroRun.runScoped(node -> {
			function push() {
				actual.push(node.localContext.get(CoroName)?.name);
			}
			push();
			node.localContext.with(new CoroName("1"));
			push();
			node.localContext.without(CoroName);
			push();
			node.localContext.without(CoroName);
			push();
			node.localContext.with(new CoroName("2"));
			push();
		});
		utest.Assert.same([null, "1", null, null, "2"], actual);
	}
}