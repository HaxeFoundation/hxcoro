package structured;

import hxcoro.elements.NonCancellable;
import hxcoro.task.ICoroNode.ICoroNodeWith;
import structured.TestThrowingScopes.FooException;

class TestLazyScopes extends atest.Test {
	function test_create_return() {
		final result = run(node -> {
			final child = node.lazy(_ -> return "foo");
			return child.await();
		});
		Assert.equals("foo", result);
	}

	function test_create_throw() {
		Assert.raises(() -> run(node -> {
			final child = node.lazy(_ -> throw new FooException());
			AssertAsync.raises(() -> child.await(), FooException);
		}), FooException);
	}

	function test_create_unlaunched() {
		Assert.raises(() -> run(node -> {
			node.lazy(_ -> {
				throw new FooException();
			});
		}), FooException);
	}

	function test_create_unlaunched_nested() {
		Assert.raises(() -> run(node -> {
			node.lazy(node -> {
				node.lazy(node -> {
					throw new FooException();
				});
			});
		}), FooException);
	}

	function test_create_unlaunched_yield() {
		Assert.raises(() -> run(node -> {
			node.lazy(_ -> {
				yield();
				throw new FooException();
			});
		}), FooException);
	}

	function test_create_unlaunched_yield_nested() {
		Assert.raises(() -> run(node -> {
			node.lazy(node -> {
				yield();
				node.lazy(node -> {
					yield();
					throw new FooException();
				});
			});
		}), FooException);
	}

	function test_create_catch() {
		final result = run(node -> {
			try {
				scope(node -> {
					final child = node.lazy(_ -> throw new FooException());
					child.await();
				});
				return "wrong";
			} catch (exc:FooException) {
				return exc.message;
			}
		});
		Assert.equals("foo", result);
	}

	function testLazyChildAddedAfterParentReturnedIsStarted() {
		var lazyRan = false;
		final task = VirtualRun.run(node -> {
			// Escapes the restricted scope, as storing the node in a field would.
			final root:ICoroNodeWith = node;
			node.async(_ -> {
				delay(10);
				root.lazy(_ -> {
					lazyRan = true;
				});
			});
			// The root lambda returns here, before the lazy child exists.
		});
		Assert.isFalse(task.isActive(), "the parent never completed");
		Assert.isTrue(lazyRan, "the late lazy child was never started");
	}

	function testLazyChildAddedWhileParentIsCancellingIsCancelled() {
		var lazyRan = false;
		final task = VirtualRun.run(node -> {
			final root:ICoroNodeWith = node;
			// NonCancellable, so it keeps running while the root is cancelling.
			node.with(new NonCancellable()).async(_ -> {
				delay(10);
				root.lazy(_ -> {
					lazyRan = true;
				});
			});
			throw new FooException();
		});
		Assert.isFalse(task.isActive(), "the parent never completed");
		Assert.isFalse(lazyRan, "the late lazy child ran although its parent is cancelling");
		Assert.isOfType(task.getError(), FooException);
	}
}
