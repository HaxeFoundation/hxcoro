package structured;

import haxe.Exception;
import hxcoro.schedulers.VirtualTimeScheduler;

class TestSupervisorScopes extends atest.Test {
	function testChildThrow() {
		final result = run(node -> {
			supervisor(node -> {
				final throwingChild = node.async(_ -> throw "oh no");
				node.awaitChildren();
				"ok";
			});
		});
		Assert.equals("ok", result);
	}

	function testChildThrowAwaitChildren() {
		final result = run(node -> {
			supervisor(node -> {
				final throwingChild = node.async(_ -> throw "oh no");
				node.awaitChildren();
				"ok";
			});
		});
		Assert.equals("ok", result);
	}

	function testChildThrowAwait() {
		run(node -> {
			AssertAsync.raises(() -> {
				supervisor(node -> {
					final throwingChild = node.async(_ -> throw "oh no");
					throwingChild.await();
				});
			}, String);
		});
	}

	function testChildThrowAwaitTransitive() {
		run(node -> {
			AssertAsync.raises(() -> {
				supervisor(node -> {
					final throwingChild = node.async(_ -> throw "oh no");
					final awaitingChild = node.async(_ -> throwingChild.await());
					awaitingChild.await();
				});
			}, String);
		});
	}

	function testThrowSelf() {
		run(node -> {
			AssertAsync.raises(() -> {
				supervisor(node -> {
					throw "oh no";
				});
			}, String);
		});
	}
}