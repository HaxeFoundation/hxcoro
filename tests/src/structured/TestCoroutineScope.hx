package structured;

import hxcoro.dispatchers.TrampolineDispatcher;
import haxe.coro.Mutex;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.schedulers.VirtualTimeScheduler;

private class FooException extends Exception {
	public function new() {
		super('foo');
	}
}

function has(what:Array<String>, has:Array<String>, hasNot:Array<String>, ?p:haxe.PosInfos) {
	for (has in has) {
		Assert.contains(has, what, null, p);
	}
	for (hasNot in hasNot) {
		Assert.notContains(hasNot, what, null, p);
	}
}

class TestCoroutineScope extends utest.Test {
	function test_scope_returning_value_suspending() {
		final expected = 'Hello, World';
		final actual   = CoroRun.run(_ -> {
			return scope(_ -> {
				yield();

				return expected;
			});
		});

		Assert.equals(expected, actual);
	}

	function test_scope_throwing_suspending() {
		CoroRun.run(_ -> {
			AssertAsync.raises(() -> CoroRun.run(_ -> {
				yield();

				throw new FooException();
			}), FooException);
		});
	}

	function test_scope_with_children() {
		final actual     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(_ -> {
			scope(node -> {
				node.async(_ -> {
					delay(500);

					actual.push(0);
				});

				node.async(_ -> {
					delay(501);

					actual.push(1);
				});
			});
		});

		task.start();

		scheduler.advanceTo(499);
		Assert.same(actual, []);
		Assert.isTrue(task.isActive());

		scheduler.advanceTo(501);
		Assert.same(actual, [ 0, 1 ]);
		Assert.isFalse(task.isActive());
	}

	function test_try_raise() {
		final acc = [];
		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}
		Assert.raises(() ->
			CoroRun.run(node -> {
				scope(_ -> {
					push("before yield");
					yield();
					push("after yield");
					throw new FooException();
					push("after throw");
				});
				push("at exit");
			}), FooException);
		has(acc, ["before yield", "after yield"], ["after throw", "at exit"]);
	}

	function test_try_catch() {
		final acc = [];
		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}
		CoroRun.run(node -> {
			try {
				scope(_ -> {
					push("before yield");
					yield();
					push("after yield");
					throw new FooException();
					push("after throw");
				});
				push("after scope");
			} catch(e:FooException) {
				push("in catch");
			}
			push("at exit");
		});
		has(acc, ["before yield", "after yield", "in catch", "at exit"], ["after throw", "after scope"]);
	}

	function test_try_raise_async() {
		final acc = [];
		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}
		Assert.raises(() -> CoroRun.run(node -> {
			node.async(_ -> {
				scope(_ -> {
					push("before yield");
					yield();
					push("after yield");
					throw new FooException();
					push("after throw");
				});
			});
			push("at exit");
		}), FooException);
		has(acc, ["before yield", "after yield", "at exit"], ["after throw"]);
	}

	function test_parent_scope_cancelling() {
		final acc       = [];
		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task      = CoroRun.with(dispatcher).createTask(node -> {
			final child = node.async(_ -> {
				try {
					scope(node -> {
						while (true) {
							delay(1);
						}
						push("scope 1");
					});
				} catch (e:CancellationException) {
					push("scope 2");
				}
			});

			delay(1000);
			child.cancel();
			push("scope 3");
		});

		task.start();
		scheduler.advanceBy(1000);

		has(acc, ["scope 2", "scope 3"], ["scope 1"]);
	}

	function test_cancel_due_to_sibling_exception1() {
		final acc = [];

		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}

		Assert.raises(() -> CoroRun.run(node -> {
			node.async(_ -> {
				scope(_ -> {
					push("before yield 2");
					yield();
					push("after yield 2");
					throw new FooException();
					push("after throw 2");
				});
			});
			node.async(_ -> {
				scope(_ -> {
					push("before yield 1");
					while (true) {
						yield();
					}
					push("after yield 1");
				});
			});
			push("at exit");
		}), FooException);
		has(acc, ["before yield 1", "before yield 2", "after yield 2", "at exit"], ["after yield 1", "after throw 2"]);
	}

	function test_cancel_due_to_sibling_exception2() {
		final acc = [];

		final mutex = new Mutex();
		function push(v:String) {
			mutex.acquire();
			acc.push(v);
			mutex.release();
		}

		Assert.raises(() -> CoroRun.run(node -> {
			node.async(_ -> {
				scope(_ -> {
					push("before yield 1");
					while (true) {
						delay(1);
					}
					push("after yield 1");
				});
			});
			node.async(_ -> {
				scope(_ -> {
					push("before yield 2");
					yield();
					push("after yield 2");
					throw new FooException();
					push("after throw 2");
				});
			});
			push("at exit");
		}), FooException);
		has(acc, ["before yield 1", "before yield 2", "after yield 2", "at exit"], ["after yield 1", "after throw 2"]);
	}
}