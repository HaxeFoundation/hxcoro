package foobarbaz;

import haxe.Exception;

class Test {
	public static function run() {
		// Simple invocation
		try {
			CoroRun.run(FooBarBaz.foo);
			throw new Exception("Expected an exception from FooBarBaz.foo");
		} catch (e:Exception) {
			checkStack(e);
		}

		// Same expectations hold when foo is invoked inside nested async scopes.
		try {
			CoroRun.run(scope -> {
				scope.async(scope -> {
					scope.async(_ -> {
						FooBarBaz.foo();
					});
				});
			});
			throw new Exception("Expected an exception from nested FooBarBaz.foo");
		} catch (e:Exception) {
			checkStack(e);
		}
	}

	static function checkStack(e:Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('foobarbaz/FooBarBaz.hx'),
			#if cpp
			// On C++ the @:coroutine function's definition line is reported rather
			// than the throw expression (see directthrow/Test.hx for the explanation).
			Line(5),  // baz definition (patchFirstCoroStack does not run on C++)
			Line(11), // baz() call in bar
			Line(15), // bar() call in foo
			#elseif hl
			// HL baz position varies by OS: line 5 (definition) on Windows/macOS,
			// line 6 (throw) on Linux. Accept either with AnyLine.
			AnyLine,  // baz (line varies by HL OS/JIT behaviour)
			Line(11), // baz() call in bar
			Line(15), // bar() call in foo
			#else
			Line(6),  // throw in baz
			Line(11), // baz() call in bar
			Line(15), // bar() call in foo
			#end
		]);
		if (r != null)
			throw r;
	}
}
