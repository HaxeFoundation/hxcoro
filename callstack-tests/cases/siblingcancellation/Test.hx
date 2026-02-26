package siblingcancellation;

import haxe.exceptions.CancellationException;

class Test {
	public static function run() {
		final result = SiblingCancellation.entry();
		checkMainStack(result.mainException);
		checkSiblingStack(result.siblingException);
	}

	// The main exception is the original haxe.Exception thrown by child1.
	static function checkMainStack(e:haxe.Exception) {
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('siblingcancellation/SiblingCancellation.hx'),
			#if hl
			// HL first-frame position is OS-dependent: definition line on
			// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
			AnyLine,  // child1() (line varies by HL OS)
			#else
			Line(20), // throw inside child1()
			#end
			Line(30), // _ -> child1() child-task entry lambda (at node.async() call)
			Line(30), // coro frame for the node.async() call (same position)
			Line(29), // coro frame for the outer context.runTask entry lambda
		]);
		if (r != null)
			throw r;
	}

	// The sibling CancellationException (caught by child2) carries the same stack
	// as the original exception that triggered the scope cancellation
	// (since hxcoro 0b56e3a: AbstractTask.cancelChildren passes the original stack).
	// On JS, stack assignment is not supported (#if !js in Convenience.hx), so the
	// sibling exception's stack contains only internal JS frames; we skip the check.
	static function checkSiblingStack(e:CancellationException) {
		#if !js
		final stack = e.stack.asArray();
		final r = new Inspector(stack).inspect([
			File('siblingcancellation/SiblingCancellation.hx'),
			#if hl
			// Same HL quirk as the main exception above.
			AnyLine,  // child1() (line varies by HL OS)
			#else
			Line(20), // throw inside child1() — not where child2 was cancelled
			#end
			Line(30), // _ -> child1() — the original throw origin, not child2's location
			Line(30), // coro frame for node.async() call (child1's creation site)
			Line(29), // coro frame for context.runTask entry lambda
		]);
		if (r != null)
			throw r;
		#end
	}
}
