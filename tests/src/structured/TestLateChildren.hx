package structured;

import hxcoro.elements.CoroName;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.InvalidTaskStateException;

/**
	Children created after the parent's own work has finished: lazy children still start, and a
	task that has completed refuses new children.
**/
class TestLateChildren extends atest.Test {
	function testContextLazyAfterParentReturned() {
		var outer:Null<ICoroTask<Any>> = null;
		var ran = false;
		VirtualRun.run(node -> {
			outer = node.async(o -> {
				final context = o.with(new CoroName("x"));
				o.async(_ -> {
					yield(); // the outer lambda has returned by now
					context.lazy(_ -> ran = true);
				});
			});
		});
		Assert.isFalse(outer.isActive(), "the outer task never completed");
		Assert.isTrue(ran, "the lazy child never ran");
	}

	function testNodeLazyAfterParentReturned() {
		var outer:Null<ICoroTask<Any>> = null;
		var ran = false;
		VirtualRun.run(node -> {
			outer = node.async(o -> {
				final escaped:CoroBaseTask<Any> = cast o;
				o.async(_ -> {
					yield(); // the outer lambda has returned by now
					escaped.lazy(_ -> ran = true);
				});
			});
		});
		Assert.isFalse(outer.isActive(), "the outer task never completed");
		Assert.isTrue(ran, "the lazy child never ran");
	}

	function testAsyncOnCompletedNodeThrows() {
		var ran = false;
		var error:Null<InvalidTaskStateException> = null;
		final task = VirtualRun.run(node -> {
			var escaped:Null<CoroBaseTask<Any>> = null;
			final t = node.async(n -> {
				escaped = cast n;
			});
			t.await();
			try {
				escaped.async(_ -> ran = true);
			} catch (e:InvalidTaskStateException) {
				error = e;
			}
			yield();
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(error, "creating a child on a completed task didn't throw");
		Assert.isFalse(ran, "a child of a completed task ran");
	}

	function testLazyOnCancelledNodeThrows() {
		var error:Null<InvalidTaskStateException> = null;
		final task = VirtualRun.run(node -> {
			var escaped:Null<CoroBaseTask<Any>> = null;
			final t = node.async(n -> {
				escaped = cast n;
				awaitCancellation();
			});
			yield();
			t.cancel();
			try {
				t.await();
			} catch (_:haxe.exceptions.CancellationException) {}
			try {
				escaped.lazy(_ -> {});
			} catch (e:InvalidTaskStateException) {
				error = e;
			}
			yield();
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(error, "creating a child on a cancelled task didn't throw");
	}

	function testContextAsyncOnCompletedNodeThrows() {
		var error:Null<InvalidTaskStateException> = null;
		final task = VirtualRun.run(node -> {
			var escaped:Null<CoroBaseTask<Any>> = null;
			final t = node.async(n -> {
				escaped = cast n;
			});
			t.await();
			try {
				escaped.with(new CoroName("late")).async(_ -> {});
			} catch (e:InvalidTaskStateException) {
				error = e;
			}
			yield();
		});
		Assert.isFalse(task.isActive());
		Assert.notNull(error, "creating a child on a completed task through its context didn't throw");
	}
}
