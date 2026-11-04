package review;

import haxe.atomic.AtomicInt;
import hxcoro.ds.Out;
import hxcoro.ds.channels.Channel;
import hxcoro.run.LoopRun;
import hxcoro.run.Setup;
import hxcoro.task.ICoroTask;
import sys.thread.Lock;
import sys.thread.Thread;

/**
	Known failures from the 1.0 review: channel races that need real threads.
	The deterministic parts of these items are in `tests/src/review`.
**/
class TestChannelRaces extends atest.Test {
	/**
		P1: bounded `tryWrite` fails spuriously under contention, so `DropNewest` throws.

		`src/hxcoro/ds/channels/bounded/BoundedWriter.hx:37-40`: `tryWrite` returns `false` if
		`state.compareExchange(Open, Locked) != Open`. A reader holding `Locked` for a moment makes
		it fail although the channel is open and has space. `write` then goes to its overflow
		handling (`:60-125`). `DropNewest` locks and pops from a buffer that may not be full, and if
		the reader emptied it in the meantime, it throws `Exception('Failed to drop newest item')`
		(`:85`). `DropOldest` (`:110`) has the same problem, and `DropWrite` (`:122`) drops the item.

		Fix: `tryWrite` uses `state.lock()` and handles `Draining`/`Closed` like `tryRead`
		(`BoundedReader.hx:74`). The Drop* branches check `buffer.wasFull()` under the lock before
		dropping, and retry the push under the same lock.
	**/
	function testDropNewestUnderContention() {
		final writesPerWriter = 20000;
		final errors = new AtomicInt(0);
		final done = new Lock();
		var firstError = null;
		Thread.create(() -> {
			final setup = Setup.createThreadPool(4);
			LoopRun.runTask(setup.loop, setup.createContext(), node -> {
				final ch = Channel.createBounded({size: 1, writeBehaviour: DropNewest(_ -> {})});
				final writersDone = new AtomicInt(0);
				for (_ in 0...2) {
					node.async(_ -> {
						for (i in 0...writesPerWriter) {
							try {
								ch.write(i);
							} catch (e:haxe.Exception) {
								if (errors.add(1) == 0) {
									firstError = e.message;
								}
							}
						}
						writersDone.add(1);
					});
				}
				node.async(_ -> {
					final out = new Out();
					while (writersDone.load() < 2) {
						ch.tryRead(out);
					}
				});
			});
			setup.close();
			done.release();
		});
		Assert.isTrue(done.wait(60.0), "the run hung");
		Assert.equals(0, errors.load(), '${errors.load()} writes threw, the first one with: $firstError');
	}

	/**
		P3: unbounded `close()` pops the read waiters without the lock.

		`src/hxcoro/ds/channels/unbounded/UnboundedWriter.hx:77-95`: after `justClosed`, the waiters
		are popped outside `lock.with`, and the comment there claims this is safe. The race partner
		is the cancellation callback in `UnboundedReader.hx:109`, which runs
		`lock.with(() -> readWaiters.remove(hostPage, obj))`. `PagedDeque.remove` shifts slots while
		`tryPop` advances, so a waiter can be skipped, which hangs its reader, or popped twice.

		Fix: drain the waiters into a local array inside the `lock.with` that sets `closed`, then
		resume them outside. Delete the misleading comment. The known failures in
		`tests/src/review/TestChannelCancellation.hx` are related; re-run them after the fix.

		The race is timing dependent: it reproduces reliably on JVM and HL and intermittently on
		eval, so the eval CI job sees it only sometimes.
	**/
	function testCloseWhileCancellingReaders() {
		final rounds = 200;
		final readers = 64;
		final done = new Lock();
		Thread.create(() -> {
			for (_ in 0...rounds) {
				final setup = Setup.createThreadPool(4);
				LoopRun.runTask(setup.loop, setup.createContext(), node -> {
					final ch = Channel.createUnbounded({});
					final tasks:Array<ICoroTask<Bool>> = [for (_ in 0...readers) node.async(_ -> ch.waitForRead())];
					// Let the readers suspend. Not all of them have to, as long as many race.
					yield();
					node.async(_ -> ch.close());
					for (i in 0...readers) {
						if (i % 2 == 0) {
							node.async(_ -> tasks[i].cancel());
						}
					}
				});
				setup.close();
			}
			done.release();
		});
		Assert.isTrue(done.wait(60.0), "a reader was never resumed, so the run hung");
	}
}
