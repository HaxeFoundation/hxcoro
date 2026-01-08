package features;

import hxcoro.task.ICoroNode;
import haxe.coro.context.Key;
import hxcoro.task.ILocalContext;

class TestCoroLocalContext extends utest.Test {
	public function test() {
		final stackKey = new Key<Array<String>>("stack");

		function visit(node:ILocalContext) {
			final element = node.localContext.get(stackKey);
			if (element == null) {
				node.localContext.set(stackKey, ["first time"]);
				return;
			}
			if (element.length == 1) {
				element.push("second time");
			} else {
				element.push('number ${element.length + 1}');
			}
		}

		final result = CoroRun.runScoped(node -> {
			final child1 = node.async(node -> {
				visit(node);
				visit(node);
				visit(node);
				node.localContext.get(stackKey);
			});
			final child2 = node.async(node -> { });
			visit(child2);
			visit(child2);
			Assert.same(["first time", "second time"], child2.localContext.get(stackKey));
			child1.await();
		});
		Assert.same(["first time", "second time", "number 3"], result);
	}
}