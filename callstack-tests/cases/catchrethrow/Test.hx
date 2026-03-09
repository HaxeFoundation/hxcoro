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
			Line(6),  // throw inside thrower()
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
