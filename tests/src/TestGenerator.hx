import hxcoro.generators.SyncGenerator;
import haxe.Unit;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.task.CoroTask;
import haxe.coro.context.Context;
import hxcoro.generators.SyncGenerator;
import haxe.Exception;

class TestGenerator extends utest.Test {
	function testSimple() {
		var iter = SyncGenerator.create(yield -> {
			yield(1);
			yield(2);
			yield(3);
		});
		Assert.same([1,2,3], [for (v in iter) v]);
	}

	function testTreeIter() {
		@:coroutine function iterTreeRec<T>(yield:Yield<T, Unit>, tree:Tree<T>) {
			yield(tree.leaf);
			if (tree.left != null) iterTreeRec(yield, tree.left);
			if (tree.right != null) iterTreeRec(yield, tree.right);
		}

		function iterTree<T>(tree:Tree<T>) {
			return SyncGenerator.create(yield -> iterTreeRec(yield, tree));
		}

		var tree:Tree<Int> = {
			leaf: 1,
			left: {
				leaf: 2,
				left: {leaf: 3},
				right: {leaf: 4, left: {leaf: 5}},
			},
			right: {
				leaf: 6,
				left: {leaf: 7}
			}
		};

		Assert.same([1,2,3,4,5,6,7], [for (v in iterTree(tree)) v]);
	}

	function testException() {
		final result = [];
		Assert.raises(() -> {
			for (i in SyncGenerator.create(yield -> {
				yield(1);
				yield(2);
				throw "oh no";
				yield(3);
			})) {
				result.push(i);
			}
		});
		Assert.same([1, 2], result);
	}

	function testValueGenerator() {
		final expected = [1, 3, 5, 7, 9, 11];
		final actual = [];
		final gen = SyncValueGenerator.create(yield -> {
			var sum = 1.;
			while (true) {
				sum += yield(sum);
			}
		});

		while (gen.hasNext()) {
			final value = gen.next(2);
			actual.push(Std.int(value));
			if (value > 10) {
				break;
			}
		}
		Assert.same(expected, actual);
	}
}

private typedef Tree<T> = {
	var leaf:T;
	var ?left:Tree<T>;
	var ?right:Tree<T>;
}
