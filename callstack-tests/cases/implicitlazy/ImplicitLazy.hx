package implicitlazy;

import haxe.Exception;
import hxcoro.run.Setup;

using hxcoro.run.ContextRun;

@:coroutine function thrower() {
	yield();
	throw new Exception("implicit lazy");
}

@:coroutine function slowThrower() {
	delay(10);
	throw new Exception("implicit lazy slow");
}

/**
	A lazy task that nobody explicitly starts — the parent coroutine simply
	returns, and the task is started implicitly via `startChildren()`.
	The task's startPos should be the `node.lazy()` call site.
**/
function entryImplicit() {
	CoroRun.run(node -> {
		node.lazy(_ -> thrower());
		// parent lambda returns here; child starts implicitly via startChildren()
	});
}

/**
	Same as entryImplicit, but a sibling async task also calls `task.await()`
	after the lazy task has been started implicitly (sibling's delay fires at 5ms,
	lazy task throws at 10ms, so the sibling's awaitContinuation runs first).
	The `doStart()` hook sets `callFrameLocked = true` so the sibling's
	`awaitContinuation` call cannot overwrite the lazy() call-site startPos.
**/
function entryImplicitThenAwaited() {
	Setup.createVirtualTrampoline().createContext().runTask(node -> {
		final task = node.lazy(_ -> slowThrower());
		node.async(node -> {
			delay(5);
			task.await();
		});
		// parent lambda returns here; both children start implicitly
	});
}
