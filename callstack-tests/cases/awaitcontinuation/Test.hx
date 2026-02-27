package awaitcontinuation;

class Test {
	public static function run() {
		try {
			AwaitContinuation.entry();
			throw new haxe.Exception("Expected an exception from AwaitContinuation.entry");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('awaitcontinuation/AwaitContinuation.hx'),
			Line(12), // throw inside the lazy lambda `_ -> throw new Exception("test")`
			Line(16), // awaitContinuation call site (task.startPos — set by awaitContinuation, not lazy())
			Line(11), // outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
