package supervisortask;

class Test {
	public static function run() {
		try {
			SupervisorTask.entry();
			throw new haxe.Exception("Expected an exception from SupervisorTask");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('supervisortask/SupervisorTask.hx'),
			#if hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // thrower() (line varies by HL OS)
			#else
			Line(13), // throw inside thrower()
			#end
			Line(19), // _ -> thrower() child-task entry lambda (at node.async() call)
			Line(19), // coro frame for the node.async() call (same position)
			Line(18), // coro frame for the supervisor() call site (callPos added in fd8002c)
			Line(17), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
