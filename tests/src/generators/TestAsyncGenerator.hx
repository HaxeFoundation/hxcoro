package generators;

import hxcoro.generators.AsyncGenerator;
import hxcoro.ds.channels.Channel;
import hxcoro.run.Setup;

class TestAsyncGenerator extends utest.Test {
	public function testChannelIterator() {
		final setup = Setup.createVirtualTrampoline();
		final actual = [];
		setup.createContext().runTask(node -> {
			final ch = Channel.createBounded({size: 3});
			ch.write(1);
			ch.write(2);
			ch.write(3);

			final it = ch.iterator();
			while (it.hasNext()) {
				final value = it.next();
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

	public function testRandomSample() {
		final setup = Setup.createVirtualTrampoline();
		final actual = [];
		setup.createContext().runTask(node -> {
			final gen = AsyncGenerator.create(gen -> {
				var i = 0;
				while (true) {
					delay(i * 50);
					gen.yield(i);
					delay(i * 50);
					i += 2;
				}
			});
			while (gen.hasNext()) {
				var value = gen.next();
				actual.push(value);
				if (value == 8) {
					gen.resume(null, null);
				}
			}
		});
		Assert.same([0, 2, 4, 6, 8], actual);
	}

	@:coroutine static public function iterateGenerator<T>(gen:AsyncGenerator<T>, f:T -> Void) {
		while (gen.hasNext()) {
			f(gen.next());
		}
	}

	static public function generatorToArray<T>(gen:AsyncGenerator<T>) {
		return CoroRun.run(node -> {
			[while (gen.hasNext()) gen.next()];
		});
	}

	public function testYieldPlusReturn() {
		final gen = AsyncGenerator.create(gen -> {
			gen.yield(1);
			gen.yield(2);
			gen.yield(3);
			return [4, 5, 6];
		});
		Assert.same([1, 2, 3, 4, 5, 6], generatorToArray(gen));
	}

	function testException() {
		final result = [];
		CoroRun.run(node -> {
			AssertAsync.raises(() -> {
				final gen = AsyncGenerator.create(gen -> {
					gen.yield(1);
					gen.yield(2);
					throw "oh no";
					gen.yield(3);
				});
				iterateGenerator(gen, result.push);
			}, String);
		});
		Assert.same([1, 2], result);
	}
}