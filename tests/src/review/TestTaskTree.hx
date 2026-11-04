package review;

import haxe.exceptions.CancellationException;
import hxcoro.elements.CoroName;
import hxcoro.TimeoutException;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;

/**
	Known failures from the 1.0 review: the task tree (items T*).

	Background:
	- `AbstractTask` (`src/hxcoro/task/AbstractTask.hx`) owns the state machine
	  `Created → Running → (CancellationRequested) → Completing|Cancelling → Completed|Cancelled`.
	  Children are a linked list guarded by a spin-lock encoded as `numActiveChildren == -1`
	  (`lockChildren`).
	- `CoroBaseTask` adds the coroutine parts: awaiters, `awaitChildren`, context.
	- `TaskKind` on `AbstractTask` decides how child outcomes affect the parent: `Concurrent` for
	  `async`/`lazy`, `Sequential` for `scope`/`timeout`/root, `SequentialSupervisor` for
	  `supervisor` (#216).

	Decisions from #215 that the tests below assert:
	- The kind of a child's outcome comes from its `StopCause` (`Cancellation` or `Failure`, #218),
	  not from the exception type. A `CancellationException` thrown while no cancellation was
	  requested is a failure (1b), which #218 implemented together with "a failure while cancelling
	  replaces the cancellation" and "only `cancel()` is gated by `NonCancellable`" (T4a); their
	  tests live in `tests/src/structured/TestStopCause.hx`. A child's cancellation never affects
	  its parent (T2) and `NonCancellable` is a boundary, not an inherited flag (T4): see
	  `tests/src/structured/TestChildOutcomes.hx` and `tests/src/elements/TestNonCancellable.hx`.
	- `await()` is cancellable (T3).
	- Creating a child on a task in a final state throws from the task constructor (T6b).
**/
class TestTaskTree extends atest.Test {
	/**
		T3: `await()` is not cancellable. Decided in #215: it becomes cancellable.

		`src/hxcoro/task/CoroBaseTask.hx:235-239`: `await` → `Coro.suspend` → `awaitContinuation` →
		`awaitingContinuations.add(cont)` (`:170-173`). `Coro.suspend` registers no cancellation
		callback, so `timeout(100, _ -> other.await())` keeps waiting for `other`, and the continuation
		is never removed from `awaitingContinuations`, which leaks with many awaiters of a long-lived
		task. The JS promise `await` in `src/hxcoro/CoroRun.hx:72` has the same shape.

		Fix: use `Coro.suspendCancellable` and remove the continuation on cancellation;
		`ThreadSafeCallbacks.add` (`concurrent/ThreadSafeCallbacks.hx`) already returns a handle.
		Mind the race between task completion and awaiter cancellation; `CancellingContinuation`
		handles the resume-vs-cancel CAS. `onCompletion` returns a handle for the same reason.

		This must land after `scopeWith` (a `scope` that takes a context): a cancelling task can then
		no longer wait for a `NonCancellable` cleanup child via `launchTask(...).await()`, because the
		`await` throws right away, and `scopeWith` is the replacement that waits non-cancellably.
	**/
	function testAwaitInTimeout() {
		var timedOut = false;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			try {
				timeout(100, _ -> other.await());
			} catch (_:TimeoutException) {
				timedOut = true;
			}
			other.cancel();
		});
		Assert.isTrue(timedOut);
		Assert.isFalse(task.isActive());
	}

	/**
		T3: cancelling a task that awaits another one directly.
	**/
	function testCancelAwaiter() {
		var awaiterActive = true;
		final task = VirtualRun.run(node -> {
			final other = node.async(_ -> awaitCancellation());
			final awaiter = node.async(_ -> other.await());
			yield();
			awaiter.cancel();
			yield();
			yield();
			awaiterActive = awaiter.isActive();
			other.cancel();
		});
		Assert.isFalse(awaiterActive, "the awaiter didn't react to cancellation");
		Assert.isFalse(task.isActive());
	}

	/**
		T5: `context.lazy` after the parent's own work has finished hangs the parent.

		`src/hxcoro/util/Convenience.hx:179` (`ContextConvenience.lazy`) only creates the task.
		`CoroBaseTask.lazy` (`CoroBaseTask.hx:125`) also starts the child right away if the parent is
		already `Completing`/`Cancelling`, because the parent has called `startChildren` already.
		Here the outer lambda has returned before the child creates the lazy task, so nothing ever
		starts it and the outer task waits for it forever.

		Fix: move the check into a shared helper used by both.
	**/
	function testContextLazyAfterParentReturned() {
		var outer:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			outer = node.async(o -> {
				final context = o.with(new CoroName("x"));
				o.async(_ -> {
					yield(); // the outer lambda has returned by now
					context.lazy(_ -> {});
				});
			});
		});
		Assert.isFalse(outer.isActive(), "the outer task never completed");
	}

	/**
		T6b: children can attach to a completed parent. Decided in #215: that is an error.

		`src/hxcoro/task/AbstractTask.hx`: `addChild` (`:461-469`) does not check the parent state, and
		`activate` (`:276-292`) only checks `parent.isCancelling()`. The child of a `Completed` parent
		runs, and if it fails, `childErrors` ignores it because the parent is final, so the error is lost.

		T6a, the race between `checkCompletion` unlocking the children (`numActiveChildren.store(0)`)
		and the `Completing → Completed` CAS, needs real threads and is not covered here.

		Decided fix: the task constructor throws, via `addChild`, if the parent is in a final state
		(`Completed`, `Cancelled`). This covers every creation path (`async`, `lazy`,
		`scope`, `Convenience.async`, `createTask` on a context), not just `async`/`lazy`. Details:
		- The check runs under the children lock. `checkCompletion` already does its final CAS while
		  holding that lock and calls `complete()` after releasing it, so `addChild` can no longer link
		  a child in a window between unlocking and the CAS (T6a); the check only has to be added.
		- `Completing` and `Cancelling` keep accepting children: a parent waiting for its children is
		  a valid parent, and the cleanup idiom from Issue47 adds a `NonCancellable` child while the
		  parent is `Cancelling`.
		- A dedicated exception type, e.g. `TaskCompletedException`, rather than `TaskException`,
		  which means "internal invariant violated". This test accepts any exception until it exists.
	**/
	function testAsyncOnCompletedNodeThrows() {
		var ran = false;
		var threw = false;
		final task = VirtualRun.run(node -> {
			var escaped:Null<CoroBaseTask<Any>> = null;
			final t = node.async(n -> {
				escaped = cast n;
			});
			t.await();
			try {
				escaped.async(_ -> ran = true);
			} catch (_:haxe.Exception) {
				threw = true;
			}
			yield();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(threw, "creating a child on a completed task didn't throw");
		Assert.isFalse(ran, "a child of a completed task ran");
	}

	/**
		T12: cancel-before-start loses the parent's cause.

		`src/hxcoro/task/AbstractTask.hx:281-283`: `if (parent != null && parent.isCancelling()) cancel();`
		uses a fresh `CancellationException`, so a child started inside a timed-out scope gets a plain
		`CancellationException` instead of the `TimeoutException`.

		Fix: `cancel(parent.cancellationException)` (the getter at `:110`).
	**/
	function testCancelBeforeStartKeepsParentCause() {
		var child:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			try {
				timeout(10, n -> {
					try {
						delay(100);
					} catch (_:CancellationException) {
						child = n.async(_ -> {});
					}
				});
			} catch (_:TimeoutException) {}
		});
		Assert.notNull(child);
		Assert.isOfType(child?.getError(), TimeoutException);
	}
}
