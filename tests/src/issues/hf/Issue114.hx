package issues.hf;

import haxe.coro.dispatchers.Dispatcher;
import hxcoro.run.Setup;
import hxcoro.concurrent.CoroSemaphore;

using hxcoro.run.ContextRun;

class Issue114 extends utest.Test {
	function test() {
		function newRunner() {
			return Setup.createEventLoopTrampoline().createContext();
		}
		var didRun = false;
		// Outer
		newRunner().runTask(node -> {
			node.context.get(Dispatcher).dispatchFunction(() -> {
				// Inner
				newRunner().runTask(node -> {
					final sem = new CoroSemaphore(0, 1);
					node.context.get(Dispatcher).dispatchFunction(() -> {
						sem.release();
						didRun = true;
					});
					sem.acquire();
				});
			});
		});
		Assert.isTrue(didRun);
	}
}