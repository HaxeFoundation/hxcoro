package review;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.ChannelClosedException;
import hxcoro.schedulers.VirtualTimeScheduler;

/**
	Known failures from the 1.0 review: primitives, channels, pipes and schedulers
	(items P*). The concurrency items that need real threads (P1's contention case, P3,
	P4, P6) are not covered here; they belong in `thread-tests/src/cases/`.

	Background: bounded channels use a small atomic state (`ds/channels/bounded/AtomicChannelState.hx`):
	`Open`, `Draining`, `Closed` in a `LockableAtomic`. `state.lock()` spins until it gets the lock and
	returns the previous state, and `tryLock(Open)` is a try-lock. Unbounded channels use a
	mutex plus `closed` flags. Waiters are stored in a `PagedDeque`, which is not thread-safe.
**/
class TestPrimitives extends atest.Test {
	/**
		P1: `DropWrite` on a closed bounded channel silently drops the item instead of throwing.

		`src/hxcoro/ds/channels/bounded/BoundedWriter.hx:37-40`: `tryWrite` returns `false` if
		`state.tryLock(Open) != Open`, which includes a closed channel, and the
		`DropWrite` branch of `write` (`:122`) then passes the item to the callback and returns. The
		other modes throw `ChannelClosedException` on a closed channel.

		The main part of P1 needs threads: a concurrent reader or writer holding the lock for a
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
}
