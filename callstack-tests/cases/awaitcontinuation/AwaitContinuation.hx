package awaitcontinuation;

import haxe.Exception;

/**
	Verifies that calling `awaitContinuation` directly (not via `await()`) also
	contributes to the exception call frame. The `awaitContinuation` call site
	should appear as a coro stack frame, just like `await()` does.
**/
function entry() {
	CoroRun.run(node -> {
		final task = node.lazy(_ -> throw new Exception("test"));
		suspend(cont -> {
			// awaitContinuation is a public method on CoroBaseTask but is not exposed
			// through the IStartableCoroTask interface, so a cast is required here.
			(cast task : CoroBaseTask<Dynamic>).awaitContinuation(cont);
		});
	});
}
