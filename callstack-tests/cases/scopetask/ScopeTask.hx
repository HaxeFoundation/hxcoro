package scopetask;

import haxe.Exception;

/**
	A child task that throws after a suspension point, running inside a `scope()` call.
	The scope task wraps the lambda: when the child task throws, the scope propagates
	the exception to the outer `CoroRun.run()` caller.
	Tests that the `scope()` call-site frame now appears in the stack (Haxe fd8002c).
**/
@:coroutine function thrower() {
	yield();
	throw new Exception("thrown in scope child");
}

function entry() {
	CoroRun.run(_ -> {
		scope(node -> {
			node.async(_ -> thrower());
		});
	});
}
