package nestedplainthrow;

class Test {
	public static function run() {
		try {
			PlainThrow.entry();
			throw new haxe.Exception("Expected an exception from PlainThrow");
		} catch (e:haxe.Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('nestedplainthrow/PlainThrow.hx'),
			#if (eval || hl || jvm)
			// On eval, HL and JVM the runtime captures the full Haxe call stack,
			// including the throw site inside the plain thrower() function and the
			// call site of thrower() inside the innermost async lambda.
			Line(7),  // throw inside thrower()
			Line(17), // thrower() call inside the innermost node.async lambda
			Line(15), // innermost node.async lambda (coro frame)
			#elseif cpp
			// On C++ the full Haxe call stack is also available for plain functions
			// via hxcpp's HX_STACK_LINE debug macros (unlike @:coroutine functions,
			// which report their definition line — see directthrow/Test.hx).
			Line(7),  // throw inside thrower()
			Line(17), // thrower() call inside the innermost node.async lambda
			Line(15), // innermost node.async lambda (coro frame)
			#else
			// On JS, Neko, Python and PHP the native exception stack only extends
			// to the outermost coroutine lambda that invoked thrower(); the plain
			// function itself does not appear as a named Haxe source frame.
			// The lambda shows up twice: once as the native call-stack frame and
			// once as the reconstructed coro-chain frame.
			Line(15), // innermost node.async lambda (native frame)
			Line(15), // innermost node.async lambda (coro chain frame)
			#end
			Line(13), // middle node.async lambda
			Line(11), // CoroRun.run lambda
		]);
		if (r != null)
			throw r;
	}
}
