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
			// On C++ the coroutine continuation's stackItem is initialized to the
			// @:coroutine function's definition line.  The patchFirstCoroStack path
			// (which would update it to the actual throw site) only runs when the
			// native exception stack contains an invokeResume frame with a .hx
			// source path; on C++ the native stack carries C++ file paths instead,
			// so no patch is applied and the definition line is kept.
			// Note: this limitation only affects @:coroutine functions — plain
			// functions are captured correctly via hxcpp's HX_STACK_LINE macros
			// (see the nestedplainthrow test case).
			Line(6),  // thrower() definition (patchFirstCoroStack does not run on C++)
			#elseif hl
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
