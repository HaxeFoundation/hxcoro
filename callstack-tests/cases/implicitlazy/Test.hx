package implicitlazy;

class Test {
	public static function run() {
		testImplicit();
		testImplicitThenAwaited();
	}

	static function testImplicit() {
		try {
			ImplicitLazy.entryImplicit();
			throw new haxe.Exception("Expected an exception from ImplicitLazy.entryImplicit");
		} catch (e:haxe.Exception) {
			checkImplicitStack(e);
		}
	}

	static function testImplicitThenAwaited() {
		try {
			ImplicitLazy.entryImplicitThenAwaited();
			throw new haxe.Exception("Expected an exception from ImplicitLazy.entryImplicitThenAwaited");
		} catch (e:haxe.Exception) {
			checkImplicitThenAwaitedStack(e);
		}
	}

	static function checkImplicitStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		// Lazy task started implicitly when parent completes (startChildren).
		// startPos = node.lazy() call site (line 25), not a start()/await() call site.
		final r = new Inspector(stack).inspect([
			File('implicitlazy/ImplicitLazy.hx'),
			#if hl
			AnyLine, // thrower() throw (line varies by HL OS)
			#else
			Line(10), // throw inside thrower()
			#end
			Line(25), // _ -> thrower() child-task entry lambda (at node.lazy() call)
			Line(25), // coro frame: task.startPos = node.lazy() call site
			Line(24), // coro frame: outer CoroRun.run() entry
		]);
		if (r != null)
			throw r;
	}

	static function checkImplicitThenAwaitedStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		// Lazy task started implicitly (startChildren), then a sibling calls task.await().
		// doStart() sets callFrameLocked = true before the sibling can call awaitContinuation,
		// so startPos is not overwritten by the sibling's await() call site.
		// startPos remains the node.lazy() call site (line 39).
		final r = new Inspector(stack).inspect([
			File('implicitlazy/ImplicitLazy.hx'),
			#if hl
			AnyLine, // slowThrower() throw (line varies by HL OS)
			#else
			Line(15), // throw inside slowThrower()
			#end
			Line(39), // _ -> slowThrower() child-task entry lambda (at node.lazy() call)
			Line(39), // coro frame: task.startPos = node.lazy() call site (NOT overwritten by sibling)
			Line(38), // coro frame: outer runTask() entry
		]);
		if (r != null)
			throw r;
	}
}
