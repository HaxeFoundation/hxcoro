package ds.channels;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.ds.Out;
import hxcoro.task.NodeLambda;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

/**
	Closing a channel while readers are suspended in it, for both channel kinds (#186).
**/
class TestChannelClose extends atest.Test {
	static function createChannels():Array<Channel<Int>> {
		return [ Channel.createBounded({ size : 4 }), Channel.createUnbounded({}) ];
	}

	static function runDeterministic<T>(lambda:NodeLambda<T>):T {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(lambda);

		task.start();
		while (task.isActive()) {
			scheduler.loop(NoWait);
			scheduler.advanceBy(1);
		}

		return task.get();
	}

	function test_wait_for_read_suspended_then_closed() {
		for (channel in createChannels()) {
			final actual = runDeterministic(node -> {
				final reader = node.async(_ -> channel.waitForRead());

				delay(1);
				channel.close();

				[ reader.await(), channel.waitForRead(), channel.tryWrite(1) ];
			});

			Assert.same([ false, false, false ], actual);
		}
	}

	function test_read_suspended_then_closed() {
		for (channel in createChannels()) {
			final actual = runDeterministic(node -> {
				final reader = node.async(_ -> {
					try {
						channel.read();
						"read";
					} catch (_:ChannelClosedException) {
						"closed";
					}
				});

				delay(1);
				channel.close();

				reader.await();
			});

			Assert.equals("closed", actual);
		}
	}

	function test_wait_for_read_suspended_then_written_and_closed() {
		for (channel in createChannels()) {
			final actual = runDeterministic(node -> {
				final reader1 = node.async(_ -> channel.waitForRead());
				final reader2 = node.async(_ -> channel.waitForRead());

				delay(1);
				Assert.isTrue(channel.tryWrite(1));
				channel.close();

				// Both readers are told there is data, but only one item can be read.
				final out    = new Out();
				final result = [ reader1.await(), reader2.await(), channel.tryRead(out), channel.tryRead(out) ];

				result.push(channel.waitForRead());
				result;
			});

			Assert.same([ true, true, true, false, false ], actual);
		}
	}
}
