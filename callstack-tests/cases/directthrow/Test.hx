package directthrow;

class Test {
	public static function run() {
		try {
			DirectThrow.entry();
			throw new haxe.Exception("Expected an exception from DirectThrow");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('directthrow/DirectThrow.hx'),
			#if cpp
			// cpp reports the coroutine function definition line rather than
			// the exact throw position (known cpp frame-position inaccuracy).
			Line(6),  // thrower() definition
			#else
			Line(7),  // throw inside thrower()
			#end
			Line(12), // thrower() call inside caller()
			Line(17), // entry lambda: _ -> caller()
			Line(17), // enclosing coro frame at the same entry line
		]);
		if (r != null)
			throw r;
	}
}
