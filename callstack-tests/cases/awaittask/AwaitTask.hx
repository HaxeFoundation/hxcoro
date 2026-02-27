package awaittask;

import haxe.Exception;

/**
	A child task that throws after a suspension point.
	The parent explicitly awaits the child via `task.await()`.
	Tests that the exception propagates correctly across the task-await boundary.
**/
@:coroutine function childThrower() {
	yield();
	throw new Exception("thrown in child task");
}

function entry() {
	CoroRun.run(node -> {
		final task = node.async(_ -> childThrower());
		yield();
		task.await();
	});
}
