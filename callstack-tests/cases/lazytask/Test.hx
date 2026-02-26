package lazytask;

class Test {
	public static function run() {
		testStart();
		testAwait();
		testTransitive();
	}

	static function testStart() {
		try {
			LazyTask.entryStart();
			throw new haxe.Exception("Expected an exception from LazyTask.entryStart");
		} catch (e:haxe.Exception) {
			checkStartStack(e);
		}
	}

	static function testAwait() {
		try {
			LazyTask.entryAwait();
			throw new haxe.Exception("Expected an exception from LazyTask.entryAwait");
		} catch (e:haxe.Exception) {
			checkAwaitStack(e);
		}
	}

	static function testTransitive() {
		try {
			LazyTask.entryTransitive();
			throw new haxe.Exception("Expected an exception from LazyTask.entryTransitive");
		} catch (e:haxe.Exception) {
			checkTransitiveStack(e);
		}
	}

	static function checkStartStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('lazytask/LazyTask.hx'),
			#if hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // thrower() (line varies by HL OS)
			#else
			Line(7),  // throw inside thrower()
			#end
			Line(12), // _ -> thrower() child-task entry lambda (at node.lazy() call)
			Line(13), // coro frame for task.start() call site (startPos set at start, not lazy creation)
			Line(11), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}

	static function checkAwaitStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('lazytask/LazyTask.hx'),
			#if hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // thrower() (line varies by HL OS)
			#else
			Line(7),  // throw inside thrower()
			#end
			Line(20), // _ -> thrower() child-task entry lambda (at node.lazy() call)
			Line(21), // coro frame for task.await() call site (startPos set at await, not lazy creation)
			Line(19), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}

	static function checkTransitiveStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		// task1 is a lazy task awaited by task2, which is started with task2.start().
		// The chain shows: throw → task1.await() call site → task2.start() call site → CoroRun.run()
		// task2 appears via callerTask (the task in the context when awaitContinuation was triggered).
		final r = new Inspector(stack).inspect([
			File('lazytask/LazyTask.hx'),
			#if hl
			AnyLine,  // thrower() (line varies by HL OS)
			#else
			Line(7),  // throw inside thrower()
			#end
			Line(27), // _ -> thrower() child-task entry lambda (at task1 node.lazy() call)
			Line(29), // coro frame for task1.await() call site inside task2's lambda (task1.startPos)
			Line(31), // coro frame for task2.start() call site (task2.startPos, via callerTask chain)
			Line(26), // coro frame for the outer CoroRun.run() entry lambda
		]);
		if (r != null)
			throw r;
	}
}
