package elements;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.elements.CoroName;
import hxcoro.schedulers.EventLoopScheduler;

class TestCoroName extends utest.Test {
	@:coroutine
	function logDebug() {
		return suspend(cont -> {
			cont.resume(cont.context.get(CoroName).name, null);
		});
	}

	function test() {
		CoroRun.runScoped(scope -> {
			scope.with(new CoroName("first name")).async(_ -> {
				Assert.equals("first name", logDebug());
			});
		});
	}

	function testScope() {
		CoroRun.runScoped(node -> {
			node.with(new CoroName("first name")).async(_ -> {
				scope(_ -> {
					Assert.equals("first name", logDebug());
				});
			});
		});
	}

	function newTrampoline() {
		return new TrampolineDispatcher(new EventLoopScheduler());
	}

	function testChildrenNames() {
		final result = CoroRun.with(newTrampoline(), new CoroName("Parent")).run(node -> {
			final children = [for (i in 0...10) node.with(new CoroName('Name: $i')).async(node -> node.context.get(CoroName).name)];
			[for (child in children) child.await()];
		});
		final expected = [for (i in 0...10) 'Name: $i'];
		Assert.same(expected, result);
	}

	function testEntrypoint() {
		CoroRun.with(newTrampoline(), new CoroName("first name")).run(scope -> {
			Assert.equals("first name", logDebug());
		});

		CoroRun.with(newTrampoline(), new CoroName("wrong name")).with(new CoroName("first name")).run(scope -> {
			Assert.equals("first name", logDebug());
		});
	}
}