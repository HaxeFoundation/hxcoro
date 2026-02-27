package cancellation;

class Test {
	public static function run() {
		try {
			CancellationTask.entry();
			throw new haxe.Exception("Expected an exception from CancellationTask");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('cancellation/CancellationTask.hx'),
			Line(13), // throw inside thrower()
			Line(18), // _ -> thrower() child-task entry lambda (at node.async() call)
			Line(18), // coro frame for the node.async() call (same position)
			Line(17), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
