package review;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.ChannelClosedException;
import hxcoro.ds.pipelines.Pipe;
import hxcoro.ds.pipelines.pipe.PipeWriter;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
	Known failures from the 1.0 review: primitives, channels, pipes and schedulers
	(items P*). The concurrency items that need real threads (P1's contention case, P3,
	P4, P6) are not covered here; they belong in `thread-tests/src/cases/`.

	Background: bounded channels use a small atomic state (`ds/channels/bounded/AtomicChannelState.hx`):
	`Open`, `Locked`, `Draining`, `Closed`. `state.lock()` spins until it gets the lock and returns
	the previous state, and `compareExchange(Open, Locked)` is a try-lock. Unbounded channels use a
	mutex plus `closed` flags. Waiters are stored in a `PagedDeque`, which is not thread-safe.
**/
class TestPrimitives extends atest.Test {
	/**
		P1: `DropWrite` on a closed bounded channel silently drops the item instead of throwing.

		`src/hxcoro/ds/channels/bounded/BoundedWriter.hx:37-40`: `tryWrite` returns `false` if
		`state.compareExchange(Open, Locked) != Open`, which includes a closed channel, and the
		`DropWrite` branch of `write` (`:122`) then passes the item to the callback and returns. The
		other modes throw `ChannelClosedException` on a closed channel.

		The main part of P1 needs threads: a concurrent reader or writer holding `Locked` for a
		moment makes `tryWrite` fail although the channel is open and has space. `DropWrite` then
		drops the item, and `DropNewest`/`DropOldest` pop from a buffer that may not be full; with size
		1 they can throw `Exception('Failed to drop newest item')`. Fix: `tryWrite` uses `state.lock()`
		and handles `Draining`/`Closed` like `tryRead` (`BoundedReader.hx:74`); the Drop* branches
		check `buffer.wasFull()` under the lock before dropping and retry the push under the same lock.
	**/
	function testDropWriteOnClosedChannelThrows() {
		final dropped = [];
		var threw = false;
		run(_ -> {
			final ch = Channel.createBounded({size: 1, writeBehaviour: DropWrite(dropped.push)});
			ch.close();
			try {
				ch.write(1);
			} catch (_:ChannelClosedException) {
				threw = true;
			}
		});
		Assert.isTrue(threw);
		Assert.same([], dropped);
	}

	/**
		P7: cancelled timers stay in the heap until their due time.

		`src/hxcoro/schedulers/ScheduledEvent.hx:52`: `close` only nulls `cont`, and the event stays
		in the `MinimumHeap` until it is due, so every `timeout(30000, ...)` and every cancelled `delay`
		leaves a dead node behind, and at high request rates the heap grows to rate × timeout. `close()`
		is also a plain write racing the read in `onDispatch`.

		Fix: track a dead-node count and rebuild the heap when dead > live (amortised O(1)), or store
		a heap index in each event for O(log n) removal under the scheduler's mutex. Make `close` an
		atomic exchange. Nothing here produces a wrong result, this is a memory and throughput item.
		The bound in this test is arbitrary; adjust it to the chosen strategy.
	**/
	function testClosedEventsLeaveHeap() {
		final scheduler = new VirtualTimeScheduler();
		for (_ in 0...10000) {
			scheduler.schedule(100000, new FunctionContinuation(Context.empty, (_, _) -> {})).close();
		}
		final length:Int = @:privateAccess scheduler.heap.length;
		Assert.isTrue(length < 100, 'heap holds $length closed events');
	}

	/**
		P8: consumed `CircularBuffer` slots keep references alive.

		`src/hxcoro/ds/CircularBuffer.hx:65-91`: `tryPopHead`/`tryPopTail` don't null the slot.
		Nulling it is safe because it happens under the channel lock.

		`src/hxcoro/thread/WorkStealingQueue.hx:81` has the same retention (`steal` leaves the
		dispatched objects in place, and storage never shrinks), but there the slot can't be nulled
		after a steal CAS because the producer may have wrapped onto it. Let the producer clear
		`[oldRead, read)` lazily in `add`, or document the retention. Not covered here. Like P7, this
		is a memory item rather than a wrong result.
	**/
	function testCircularBufferPopClearsSlot() {
		final buffer = new CircularBuffer<Array<Int>>(2);
		final out = new Out();
		buffer.tryPush([1]);
		buffer.tryPopTail(out);
		Assert.isNull(@:privateAccess buffer.storage[0], "tryPopTail kept the item");
		buffer.tryPush([2]);
		buffer.tryPopHead(out);
		Assert.isNull(@:privateAccess buffer.storage[1], "tryPopHead kept the item");
	}

	/**
		P9: `PipeWriter.flush` is not exception-safe.

		`src/hxcoro/ds/pipelines/pipe/PipeWriter.hx:60-66`: `state.count.add(chunk.byteLength)` runs
		before each `write`, and `pending` is only cleared at the end. If a `write` throws (closed,
		cancelled), `count` stays inflated, so the pause thresholds are wrong, and a retried `flush`
		resends the chunks that were already written. Writing to the closed unbounded channel throws
		on the first chunk here, so this test covers the `count` part.

		Fix: remove each chunk from `pending` and add to `count` only after its write succeeds, or
		roll `count` back on exception.
	**/
	function testFailedFlushDoesNotCountChunks() {
		final pipe = Pipe.create();
		final writer:PipeWriter = cast pipe.writer;
		var threw = false;
		run(_ -> {
			writer.getBuffer(4);
			writer.advance(4);
			writer.close();
			try {
				writer.flush();
			} catch (_:ChannelClosedException) {
				threw = true;
			}
		});
		Assert.isTrue(threw);
		Assert.equals(0, @:privateAccess writer.state.count.load());
	}
}
