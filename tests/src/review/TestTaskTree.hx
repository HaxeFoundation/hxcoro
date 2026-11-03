package review;

import haxe.exceptions.CancellationException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.elements.CoroName;
import hxcoro.elements.NonCancellable;
import hxcoro.exceptions.TimeoutException;
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
	- A node strategy decides how child outcomes affect the parent: `CoroChildStrategy` for
	  `async`/`lazy`, `CoroScopeStrategy` for `scope`/root, `CoroSupervisorStrategy`.
**/
class TestTaskTree extends atest.Test {
	/**
		T2: `cancelChildren()` inside `async` cancels the node itself. Needs a maintainer decision.

		`src/hxcoro/task/node/CoroChildStrategy.hx:31-33`: `childCancels` calls `task.cancel(cause)`,
		while `CoroScopeStrategy.hx:31` and `CoroSupervisorStrategy.hx:24` are no-ops. Routing is in
		`AbstractTask.childCompletes`: a child that ends with a `CancellationException` goes to
		`childCancels`. `ICoroNode.cancelChildren` is documented as not cancelling the node.

		The children complete after the node has returned 42, so the node is `Completing`, and
		`childCancels` moves it to `Cancelling`.

		The docs contradict each other: `CoroChildStrategy`'s class doc says async tasks are
		cancelled when a child is cancelled, `ICoroNode.cancelChildren` says the node is not. No test
		in the regular suite depends on the current behaviour: with `CoroChildStrategy.childCancels`
		made a no-op, the whole suite still passes.

		Proposed semantics (Kotlin): a child ending with a `CancellationException` never cancels its
		parent, so `childCancels` is a no-op in all strategies. Open question: whether an escaped
		`TimeoutException` (a `CancellationException` subclass) counts as a failure; today it cancels
		an async parent but is swallowed under scope/root.
	**/
	function testCancelChildrenDoesNotCancelAsyncNode() {
		var t:Null<ICoroTask<Int>> = null;
		VirtualRun.run(node -> {
			t = node.async(n -> {
				n.async(_ -> awaitCancellation());
				n.async(_ -> awaitCancellation());
				yield();
				n.cancelChildren();
				return 42;
			});
		});
		Assert.isFalse(t.isActive());
		Assert.isNull(t.getError());
		Assert.equals(42, t.get());
	}

	/**
		T2: same as above, cancelling a single child with `child.cancel()`.
	**/
	function testCancelChildDoesNotCancelAsyncNode() {
		var t:Null<ICoroTask<Int>> = null;
		VirtualRun.run(node -> {
			t = node.async(n -> {
				final child = n.async(_ -> awaitCancellation());
				yield();
				child.cancel();
				return 42;
			});
		});
		Assert.isFalse(t.isActive());
		Assert.isNull(t.getError());
		Assert.equals(42, t.get());
	}

	/**
		T3: `await()` is not cancellable. Needs a maintainer decision (public behaviour).

		`src/hxcoro/task/CoroBaseTask.hx:235-239`: `await` → `Coro.suspend` → `awaitContinuation` →
		`awaitingContinuations.add(cont)` (`:170-173`). `Coro.suspend` registers no cancellation
		callback, so `timeout(100, _ -> other.await())` keeps waiting for `other`, and the continuation
		is never removed from `awaitingContinuations`, which leaks with many awaiters of a long-lived
		task. The JS promise `await` in `src/hxcoro/CoroRun.hx:72` has the same shape.

		Fix: use `Coro.suspendCancellable` and remove the continuation on cancellation;
		`ThreadSafeCallbacks.add` (`concurrent/ThreadSafeCallbacks.hx`) already returns a handle.
		Mind the race between task completion and awaiter cancellation; `CancellingContinuation`
		handles the resume-vs-cancel CAS.
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
		T4a: `NonCancellable` swallows child failures. Needs a maintainer decision.

		`src/hxcoro/task/CoroBaseTask.hx:201-206`: `override function doCancel(error)` returns early if
		`context.get(NonCancellable) != null`. `doCancel` is also the path for child errors
		(`CoroChildStrategy.childErrors` and the scope strategy) and for `setInternalException`
		(`AbstractTask.hx:388-391`), so a failing child of a NonCancellable task is ignored and "boom"
		is lost.

		The regular suite already asserts in `tests/src/elements/TestNonCancellable.hx`
		(`testFailurePropagatesToParent`) that a NonCancellable task's own exception fails it and
		propagates to its parent, because `ownWorkFails` bypasses `doCancel`. So today a task's own
		failure counts, but the same failure in a child is dropped.

		Proposed fix: distinguish external cancellation (parent `cancelChildren`, the parent check in
		`activate`, user `cancel()`) from failure (`childErrors`, internal errors), and ignore only the
		former. For comparison, Kotlin's `NonCancellable` doesn't fail the parent either; the child's
		exception goes to the uncaught exception handler. Either outcome is acceptable, losing the
		error silently is not.
	**/
	function testNonCancellableKeepsChildError() {
		var t:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			t = node.with(new NonCancellable()).async(n -> {
				n.async(_ -> {
					throw "boom";
				});
				delay(10);
			});
		});
		Assert.isFalse(t.isActive());
		Assert.equals("boom", t.getError()?.message);
	}

	/**
		T4b: `timeout` inside a `NonCancellable` task never takes effect, because the element is
		inherited by every descendant via the context, including the scope `timeout` creates.
		`NonCancellable`'s doc says it prevents cancellation of "tasks created in its context,
		including through cancellation of their parent", so this is as documented. The test asserts
		Kotlin's semantics instead, where `withTimeout` works inside `NonCancellable`.

		Proposed fix: scopes created inside should not inherit `NonCancellable`. Kotlin's
		`NonCancellable` is a Job, not an inherited flag. Possibly strip the element when creating
		`scope`/`timeout`/`async` children.
	**/
	function testTimeoutInsideNonCancellable() {
		var timedOut = false;
		VirtualRun.run(node -> {
			node.with(new NonCancellable()).async(_ -> {
				try {
					timeout(10, _ -> delay(100));
				} catch (_:TimeoutException) {
					timedOut = true;
				}
			});
		});
		Assert.isTrue(timedOut);
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
		T6b: children can attach to a completed parent.

		`src/hxcoro/task/AbstractTask.hx`: `addChild` (`:461-469`) does not check the parent state, and
		`activate` (`:276-292`) only checks `parent.isCancelling()`. The child of a `Completed` parent
		runs, and if it fails, `childErrors` ignores it because the parent is final, so the error is lost.

		T6a, the race between `checkCompletion` unlocking the children (`numActiveChildren.store(0)`)
		and the `Completing → Completed` CAS, needs real threads and is not covered here.

		Fix: make `addChild` refuse or immediately cancel a child whose parent is final, and document
		it. This test expects the child to be cancelled without running; if reporting the error is
		chosen instead, adapt it. Mind T7: don't call `complete()` under the children lock.
	**/
	function testAsyncOnCompletedNode() {
		var ran = false;
		var child:Null<ICoroTask<Any>> = null;
		VirtualRun.run(node -> {
			var escaped:Null<CoroBaseTask<Any>> = null;
			final t = node.async(n -> {
				escaped = cast n;
			});
			t.await();
			child = escaped.async(_ -> {
				ran = true;
				throw "x";
			});
			yield();
		}, 1000, _ -> {});
		Assert.isFalse(ran, "a child of a completed task ran");
		Assert.isOfType(child.getError(), CancellationException);
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

	/**
		T14: `awaitChildren` has a single waiter slot.

		`CoroBaseTask.hx:57` (`awaitingChildContinuation`) and `:218-229`. Two concurrent callers,
		possible through an escaped node, overwrite each other and one never wakes. Here the node's own
		`awaitChildren` is overwritten by the one of `other`, so the node never finishes.

		Fix: use a list (e.g. `ThreadSafeCallbacks`), or throw on a second concurrent waiter. Do this
		together with T7.
	**/
	function testTwoAwaitChildrenCallers() {
		var woken = 0;
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			var escaped:Null<CoroBaseTask<Any>> = null;
			node.async(n -> {
				escaped = cast n;
				n.async(_ -> latch.wait());
				n.awaitChildren();
				woken++;
			});
			yield();
			node.async(_ -> {
				escaped.awaitChildren();
				woken++;
			});
			yield();
			latch.arrive(1);
		});
		Assert.equals(2, woken);
		Assert.isFalse(task.isActive());
	}
}
