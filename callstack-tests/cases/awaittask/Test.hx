package awaittask;

class Test {
	public static function run() {
		try {
			AwaitTask.entry();
			throw new haxe.Exception("Expected an exception from AwaitTask");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('awaittask/AwaitTask.hx'),
			Line(12), // throw inside childThrower()
			Line(17), // _ -> childThrower() child-task entry lambda (at node.async() call)
			Line(17), // coro frame for the node.async() call (same position)
			Line(16), // coro frame for the outer CoroRun.run() entry lambda
			// Note: task.await() at line 19 does not appear as a separate stack frame.
			// The child task's continuation chain is captured when the child throws:
			// it links back to where the child was CREATED (node.async, line 17),
			// not where the parent is currently WAITING (task.await, line 19).
		]);
		if (r != null)
			throw r;
	}
}
