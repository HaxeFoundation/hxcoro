package asyncscope;

import haxe.Exception;

/**
	An exception thrown from inside a `scope.async()` child coroutine.
	Tests that the exception propagates back to the parent CoroRun.run() caller.
**/
@:coroutine function inner() {
	yield();
	throw new Exception("from inner async scope");
}

@:coroutine function outer() {
	yield();
	inner();
}

function entry() {
	CoroRun.run(scope -> {
		scope.async(_ -> outer());
	});
}
