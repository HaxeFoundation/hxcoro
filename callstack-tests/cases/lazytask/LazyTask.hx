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

function entryTransitive() {
	CoroRun.run(node -> {
		final task1 = node.lazy(_ -> thrower());
		final task2 = node.lazy(node -> {
			task1.await();
		});
		task2.start();
		task2.await();
	});
}
