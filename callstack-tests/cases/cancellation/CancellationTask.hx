package cancellation;

import haxe.Exception;

/**
	A child task that throws, causing the parent scope to be cancelled.
	No explicit `task.await()` — the parent scope absorbs the child's error and
	re-throws it at the `CoroRun.run()` level via `CoroChildStrategy.childErrors`.
	Tests that the exception propagates with the correct throw-site stack.
**/
@:coroutine function thrower() {
	yield();
	throw new Exception("thrown in child task");
}

function entry() {
	CoroRun.run(node -> {
		node.async(_ -> thrower());
	});
}
