package ds.channels;

import hxcoro.ds.channels.Channel;
import hxcoro.run.Setup;

class TestChannelIterator extends atest.Test {
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
}
