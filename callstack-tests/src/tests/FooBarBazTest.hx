package tests;

import haxe.Exception;

class FooBarBazTest {
	public static function run() {
		// Simple invocation
		try {
			CoroRun.run(foobarbaz.FooBarBaz.foo);
			throw new Exception("Expected an exception from FooBarBaz.foo");
		} catch (e:Exception) {
			checkStack(e);
		}

		// Same expectations hold when foo is invoked inside nested async scopes.
		try {
			CoroRun.run(scope -> {
				scope.async(scope -> {
					scope.async(_ -> {
						foobarbaz.FooBarBaz.foo();
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
			Line(6),  // throw new Exception in baz
			Line(11), // baz() call in bar
			// TODO: sync stack (foo calling bar) not reconstructed yet
		]);
		if (r != null)
			throw r;
	}
}
