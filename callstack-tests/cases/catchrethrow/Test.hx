package catchrethrow;

class Test {
	public static function run() {
		try {
			CatchRethrow.entry();
			throw new haxe.Exception("Expected an exception from CatchRethrow");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('catchrethrow/CatchRethrow.hx'),
			#if cpp
			// On C++ the @:coroutine function's definition line is reported rather
			// than the throw expression (see directthrow/Test.hx for the explanation).
			Line(5),  // thrower() definition (patchFirstCoroStack does not run on C++)
			#elseif hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // thrower() (line varies by HL OS)
			#else
			Line(6),  // throw inside thrower()
			#end
			Line(12), // thrower() call inside catcher()'s try block
			Line(19), // entry lambda: _ -> catcher()
			Line(19), // enclosing coro frame
			// Haxe appends the rethrow site to the exception stack, so
			// re-raising at line 14 appends catcher()'s call path again:
			Line(14), // "throw e" rethrow inside catcher()
			Line(19), // entry lambda repeated
			Line(19), // coro frame repeated
		]);
		if (r != null)
			throw r;
	}
}
