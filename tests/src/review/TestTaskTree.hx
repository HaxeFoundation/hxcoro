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
	- `await()` is cancellable (T3). The remaining items of the review, T5, T6b and T12, were
	  implemented in phase 3; their tests live in `tests/src/structured/TestLateChildren.hx` and
	  `tests/src/structured/TestStopCause.hx`.
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
}
