package timeout;

import hxcoro.exceptions.TimeoutException;

class Test {
	public static function run() {
		try {
			Timeout.entry();
			throw new haxe.Exception("Expected a TimeoutException from Timeout");
		} catch (e:TimeoutException) {
			checkStack(e);
		}
	}

	static function checkStack(e:TimeoutException) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('hxcoro/Coro.hx'),
			AnyLine,  // timeout() state machine frame (line varies by target/platform)
			File('timeout/Timeout.hx'),
			Line(18), // LocalFunction: entry lambda for task1 (the `node -> { timeout(...) }` lambda)
			Line(17), // coro frame for the node.async() call site
			Line(16), // coro frame for the outer runTask() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
