package siblingcancellation;

import haxe.exceptions.CancellationException;
import hxcoro.run.Setup;
using hxcoro.run.ContextRun;

/**
	Two child tasks share a scope. `child1` uses `delay(2)` before throwing;
	`child2` loops with `delay(1)`. When `child1` throws, the scope cancels all
	siblings, so `child2` receives a `CancellationException`. Since
	`AbstractTask.doCancel` (hxcoro 0b56e3a) propagates the original exception's
	stack to the `CancellationException`, `child2` can inspect where the original
	error was thrown.

	Uses `VirtualTimeScheduler` to guarantee deterministic ordering:
	`child2` suspends at `delay(1)` before `child1` throws at `delay(2)`.
**/
@:coroutine function child1() {
	delay(2);
	throw new haxe.Exception("thrown in child1");
}

function entry():{mainException:haxe.Exception, siblingException:CancellationException} {
	var siblingException:Null<CancellationException> = null;
	var mainException:Null<haxe.Exception> = null;
	final setup = Setup.createVirtualTrampoline();
	final context = setup.createContext();
	try {
		context.runTask(node -> {
			node.async(_ -> child1());
			node.async(_ -> {
				try {
					while (true) {
						delay(1);
					}
				} catch (e:CancellationException) {
					siblingException = e;
				}
			});
		});
	} catch (e:haxe.Exception) {
		mainException = e;
	}
	if (mainException == null)
		throw new haxe.Exception("Expected main exception from entry()");
	if (siblingException == null)
		throw new haxe.Exception("Expected sibling CancellationException from entry()");
	return {mainException: mainException, siblingException: siblingException};
}
