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
			#if hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // thrower() (line varies by HL OS)
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
