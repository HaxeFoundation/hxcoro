package supervisortask;

import haxe.Exception;

/**
	A child task that throws, running inside a `Coro.supervisor()` scope.
	The supervisor absorbs child errors (the parent does not cancel), but
	the parent explicitly awaits the child with `task.await()`, which re-throws.
	Tests that the supervisor-scope frame (`hxcoro/Coro.hx`) appears in the chain.
**/
@:coroutine function thrower() {
	yield();
	throw new Exception("thrown in supervisor child");
}

function entry() {
	CoroRun.run(_ -> {
		supervisor(node -> {
			final task = node.async(_ -> thrower());
			task.await();
		});
	});
}
