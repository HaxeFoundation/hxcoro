package generators;

import hxcoro.generators.AsyncGenerator;
import hxcoro.generators.Yield;
import hxcoro.generators.HaxeGenerator;
import hxcoro.generators.Es6Generator;
import hxcoro.generators.CsGenerator;
import haxe.Unit;

using Lambda;

class TestGenerator extends utest.Test {
	function testSimple() {
		var iter = HaxeGenerator.create(yield -> {
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

		function iterTreeHaxe<T>(tree:Tree<T>) {
			return HaxeGenerator.create(yield -> iterTreeRec(yield, tree));
		}

		function iterTreeEs6<T>(tree:Tree<T>) {
			return Es6Generator.create(yield -> iterTreeRec(yield, tree));
		}

		function iterTreeCs<T>(tree:Tree<T>) {
			return CsGenerator.create(yield -> {
				iterTreeRec(yield, tree);
				null;
			});
		}

		function iterTreeAsync<T>(tree:Tree<T>) {
			return AsyncGenerator.create(yield -> {
				iterTreeRec(yield, tree);
			});
		}

		Assert.same([1,2,3,4,5,6,7], [for (v in iterTreeHaxe(tree)) v]);
		Assert.same([1,2,3,4,5,6,7], [for (v in iterTreeEs6(tree)) v]);
		Assert.same([1,2,3,4,5,6,7], [for (v in iterTreeCs(tree)) v]);
		Assert.same([1,2,3,4,5,6,7], TestAsyncGenerator.generatorToArray(iterTreeAsync(tree)));
	}

	function testException() {
		final result = [];
		Assert.raises(() -> {
			for (i in HaxeGenerator.create(yield -> {
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

	function testEs6Generator() {
		final expected = [1, 3, 5, 7, 9, 11];
		final actual = [];
		final gen = Es6Generator.create(yield -> {
			var sum = 1.;
			while (true) {
				sum += yield.next(sum);
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

	function testCsGeneratorYieldReturn() {
		var iter = CsGenerator.create(yield -> {
			yield.yieldReturn(1);
			yield.yieldReturn(2);
			yield.yieldReturn(3);
			return null;
		});
		Assert.same([1,2,3], [for (v in iter) v]);
	}

	function testCsGeneratorYieldBreak() {
		var iter = CsGenerator.create(yield -> {
			yield.yieldBreak();
			yield.yieldReturn(1);
			yield.yieldReturn(2);
			yield.yieldReturn(3);
			return [4, 5, 6];
		});
		Assert.same([], [for (v in iter) v]);
	}

	function testCsGeneratorReturn() {
		var iter = CsGenerator.create(yield -> {
			return [4, 5, 6];
		});
		Assert.same([4, 5, 6], [for (v in iter) v]);
	}

	function testCsGeneratorYieldReturnPlusReturn() {
		var iter = CsGenerator.create(yield -> {
			yield.yieldReturn(1);
			yield.yieldReturn(2);
			yield.yieldReturn(3);
			return [4, 5, 6];
		});
		Assert.same([1, 2, 3, 4, 5, 6], [for (v in iter) v]);
	}

	function testCsGeneratorYieldReturnPlusYieldBreak() {
		var iter = CsGenerator.create(yield -> {
			yield.yieldReturn(1);
			yield.yieldReturn(2);
			yield.yieldReturn(3);
			yield.yieldBreak();
			return [4, 5, 6];
		});
		Assert.same([1, 2, 3], [for (v in iter) v]);
	}

	function testCsGeneratorYieldBreakPlusReturn() {
		var iter = CsGenerator.create(yield -> {
			yield.yieldBreak();
			return [4, 5, 6];
		});
		Assert.same([], [for (v in iter) v]);
	}

	function testTakeWhilePositive() {
		function TakeWhilePositiveHaxe(numbers:Iterable<Int>):Iterable<Int> {
			return HaxeGenerator.create(yield -> {
				for (n in numbers) {
					if (n > 0) {
						yield(n);
					} else {
						return;
					}
				}
			});
		}

		function TakeWhilePositiveCs(numbers:Iterable<Int>):Iterable<Int> {
			return CsGenerator.create(yield -> {
				for (n in numbers) {
					if (n > 0) {
						yield.yieldReturn(n);
					} else {
						yield.yieldBreak();
					}
				}
				return null;
			});
		}

		function TakeWhilePositiveEs6(numbers:Iterable<Int>):Iterable<Int> {
			return Es6Generator.create(yield -> {
				for (n in numbers) {
					if (n > 0) {
						yield.next(n);
					} else {
						return;
					}
				}
			});
		}

		function TakeWhilePositiveAsync(numbers:Iterable<Int>) {
			return AsyncGenerator.create(gen -> {
				for (n in numbers) {
					if (n > 0) {
						gen.yield(n);
					} else {
						break;
					}
				}
				return null;
			});
		}

		final arrays = [
			[2, 3, 4, 5, -1, 3, 4],
			[9, 8, 7]
		];
		final expected = [
			[2, 3, 4, 5],
			[9, 8, 7]
		];
		for (i in 0...arrays.length) {
			Assert.same(expected[i], TakeWhilePositiveHaxe(arrays[i]).array());
			Assert.same(expected[i], TakeWhilePositiveCs(arrays[i]).array());
			Assert.same(expected[i], TakeWhilePositiveEs6(arrays[i]).array());
			Assert.same(expected[i], TestAsyncGenerator.generatorToArray(TakeWhilePositiveAsync(arrays[i])));
		}
	}
}

private typedef Tree<T> = {
	var leaf:T;
	var ?left:Tree<T>;
	var ?right:Tree<T>;
}
