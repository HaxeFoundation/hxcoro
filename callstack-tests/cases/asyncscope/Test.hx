package asyncscope;

class Test {
	public static function run() {
		try {
			AsyncScope.entry();
			throw new haxe.Exception("Expected an exception from AsyncScope");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('asyncscope/AsyncScope.hx'),
			#if cpp
			// cpp reports the coroutine function definition line rather than
			// the exact throw position (known cpp frame-position inaccuracy).
			Line(9),  // inner() definition
			#elseif hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // inner() (line varies by HL OS)
			#else
			Line(11), // throw inside inner()
			#end
			Line(16), // inner() call inside outer()
			Line(21), // lambda _ -> outer() passed to scope.async()
			Line(21), // coro frame for the scope.async() call site
			Line(20), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
