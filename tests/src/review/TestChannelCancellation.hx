package review;

import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.exceptions.ChannelClosedException;
import hxcoro.task.ICoroTask;

/**
	Known failures from the 1.0 review: channels and cancellation.

	Waking a waiter only dispatches its resumption. On the trampoline used by `VirtualRun`
	that resumption runs after the current frame, so cancelling the waiter in the same frame
	deterministically hits the window that a `timeout` or another thread hits on a thread pool.
**/
class TestChannelCancellation extends atest.Test {
	/**
		`close` pops every waiter and stores `Closed`. The cancellation callback of a reader whose
		wake-up is still pending then throws `InvalidChannelStateException`. That exception is
		reported as an uncaught exception on the dispatcher.
	**/
	function testCancelReaderAfterClose() {
		var cancelError:Dynamic = null;
		final errors:Array<haxe.Exception> = [];
		final task = VirtualRun.run(node -> {
			final ch = Channel.createBounded({size: 1});
			final reader = node.async(_ -> ch.waitForRead());
			yield(); // the reader suspends on the empty channel
			ch.close(); // dispatches the reader's wake-up and stores Closed
			try {
				reader.cancel();
			} catch (e:Dynamic) {
				cancelError = e;
			}
		}, 1000, errors.push);
		Assert.isNull(cancelError, 'reader.cancel() threw $cancelError');
		Assert.same([], [for (e in errors) e.message], "the cancellation callback threw");
		Assert.isFalse(task.isActive());
	}

	/**
		Same as above for a writer suspended on a full channel. Closing a full channel moves it
		to `Draining`, so the remaining item is read first, which moves it to `Closed`.
	**/
	function testCancelWriterAfterClose() {
		var cancelError:Dynamic = null;
		final errors:Array<haxe.Exception> = [];
		final task = VirtualRun.run(node -> {
			final ch = Channel.createBounded({size: 1});
			ch.write(0);
			final writer = node.async(_ -> ch.waitForWrite());
			yield(); // the writer suspends on the full channel
			ch.close(); // dispatches the writer's wake-up and stores Draining
			ch.tryRead(new Out()); // drains the last item, which stores Closed
			try {
				writer.cancel();
			} catch (e:Dynamic) {
				cancelError = e;
			}
		}, 1000, errors.push);
		Assert.isNull(cancelError, 'writer.cancel() threw $cancelError');
		Assert.same([], [for (e in errors) e.message], "the cancellation callback threw");
		Assert.isFalse(task.isActive());
	}

	/**
		Exactly one waiting writer is popped per free slot. If that writer is cancelled before
		its wake-up runs, the wake-up is dropped instead of being handed to the next writer, so
		the next writer sleeps although there is space.
	**/
	function testWriterWakeUpIsHandedOnWhenWaiterIsCancelled() {
		var w2:Null<ICoroTask<Any>> = null;
		final task = VirtualRun.run(node -> {
			final ch = Channel.createBounded({size: 1});
			ch.write(0); // full
			final w1 = node.async(_ -> ch.write(1));
			w2 = node.async(_ -> ch.write(2));
			yield(); // both writers suspend
			final out = new Out();
			ch.tryRead(out); // frees the slot and pops w1
			w1.cancel(); // w1 loses its wake-up to cancellation
			w2.await();
		});
		Assert.isFalse(task.isActive(), "the second writer was never woken up although the channel has space");
	}

	/**
		Same as above for readers: an item is written but the only reader that was popped for it
		is cancelled, so the next reader sleeps although the channel has data.
	**/
	function testReaderWakeUpIsHandedOnWhenWaiterIsCancelled() {
		final task = VirtualRun.run(node -> {
			final ch = Channel.createBounded({size: 1});
			final r1 = node.async(_ -> ch.waitForRead());
			final r2 = node.async(_ -> ch.waitForRead());
			yield(); // both readers suspend
			ch.tryWrite(1); // pops r1
			r1.cancel(); // r1 loses its wake-up to cancellation
			r2.await();
		});
		Assert.isFalse(task.isActive(), "the second reader was never woken up although the channel has data");
	}

	/**
		Unbounded `write` checks `waitForWrite` first, which returns `false` if cancellation was
		requested. `write` then reports the open channel as closed.
	**/
	function testUnboundedWriteDuringCancellationDoesNotReportClosed() {
		var writeError:Dynamic = null;
		final task = VirtualRun.run(node -> {
			final ch = Channel.createUnbounded({});
			final writer = node.async(_ -> {
				try {
					delay(100);
				} catch (_:haxe.exceptions.CancellationException) {
					try {
						ch.write(1);
					} catch (e:Dynamic) {
						writeError = e;
					}
				}
			});
			delay(10);
			writer.cancel();
		});
		Assert.isFalse(task.isActive());
		Assert.isFalse(Std.isOfType(writeError, ChannelClosedException), "write reported an open channel as closed");
	}
}
