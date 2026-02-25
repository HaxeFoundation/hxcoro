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
			// cpp reports the coroutine definition line rather than the exact
			// throw position (inaccurate top-frame positions on cpp).
			Line(5),  // baz definition
			Line(11), // baz() call in bar
			#else
			Line(6),  // throw in baz
			Line(11), // baz() call in bar
			// TODO: sync stack (foo calling bar at line 15) not reconstructed yet
			#end
		]);
		if (r != null)
			throw r;
	}
}
