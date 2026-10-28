package generators;

import hxcoro.generators.AsyncGenerator;
import hxcoro.ds.channels.Channel;
import hxcoro.run.Setup;

class TestAsyncGenerator extends atest.Test {
	public function testChannelIterator() {
		final setup = Setup.createVirtualTrampoline();
		final actual = [];
		setup.createContext().runTask(node -> {
			final ch = Channel.createBounded({size: 3});
			ch.write(1);
			ch.write(2);
			ch.write(3);

			for (value in ch) {
				actual.push(value);
				if (value == 3) {
					ch.write(4);
					ch.write(5);
					ch.write(6);
				} else if (value == 6) {
					ch.close();
				}
				delay(1);
			}
		});
		Assert.same([1, 2, 3, 4, 5, 6], actual);
	}

	public function testChannelIteratorClosed() {
		final setup = Setup.createVirtualTrampoline();
		final actual = [];
		setup.createContext().runTask(node -> {
			final ch = Channel.createUnbounded({});
			ch.write(1);
			ch.write(2);
			ch.write(3);
			ch.close();

			for (value in ch) {
				actual.push(value);
			}
		});
		Assert.same([1, 2, 3], actual);
	}

	public function testRandomSample() {
		final setup = Setup.createVirtualTrampoline();
		final actual = [];
		setup.createContext().runTask(node -> {
			final gen = AsyncGenerator.create(yield -> {
				var i = 0;
				while (true) {
					delay(i * 50);
					yield(i);
					delay(i * 50);
					i += 2;
				}
			});
			for (value in gen) {
				actual.push(value);
				if (value == 8) {
					break;
				}
			}
		});
		Assert.same([0, 2, 4, 6, 8], actual);
	}

	@:coroutine static public function iterateGenerator<T>(gen:AsyncGenerator<T>, f:T -> Void) {
		for (value in gen) {
			f(value);
		}
	}

	static public function generatorToArray<T>(gen:AsyncGenerator<T>) {
		return run(node -> {
			[for (v in gen) v];
		});
	}

	public function testYieldPlusReturn() {
		final gen = AsyncGenerator.create(yield -> {
			yield(1);
			yield(2);
			yield(3);
			return [4, 5, 6];
		});
		Assert.same([1, 2, 3, 4, 5, 6], generatorToArray(gen));
	}

	function testException() {
		final result = [];
		run(node -> {
			AssertAsync.raises(() -> {
				final gen = AsyncGenerator.create(yield -> {
					yield(1);
					yield(2);
					throw "oh no";
					yield(3);
				});
				iterateGenerator(gen, result.push);
			}, String);
		});
		Assert.same([1, 2], result);
	}
}