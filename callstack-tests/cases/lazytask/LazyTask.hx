package lazytask;

import haxe.Exception;

@:coroutine function thrower() {
	yield();
	throw new Exception("thrown in lazy child");
}

function entryStart() {
	CoroRun.run(node -> {
		final task = node.lazy(_ -> thrower());
		task.start();
		task.await();
	});
}

function entryAwait() {
	CoroRun.run(node -> {
		final task = node.lazy(_ -> thrower());
		task.await();
	});
}
