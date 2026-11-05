package structured;

import haxe.exceptions.CoroutineException;
import hxcoro.elements.CoroName;
import hxcoro.run.Setup;

/**
	`async` and `lazy` on a context create children of the task in that context.
**/
class TestContextChildren extends atest.Test {
	function testAsyncWithoutTaskThrows() {
		final context = Setup.createTrampoline().createContext();
		Assert.raises(() -> context.async(_ -> 1), CoroutineException);
	}

	function testLazyWithoutTaskThrows() {
		final context = Setup.createTrampoline().createContext();
		Assert.raises(() -> context.lazy(_ -> 1), CoroutineException);
	}

	function testAsyncWithTaskCreatesChild() {
		var childDone = false;
		final task = VirtualRun.run(node -> {
			node.with(new CoroName("child")).async(_ -> {
				delay(5);
				childDone = true;
			});
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(childDone, "the parent completed before its child");
	}
}
