package review;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.bounded.AtomicChannelState.ChannelState;
import hxcoro.ds.channels.bounded.BoundedWriter;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;

/**
	Known failures from the 1.0 review: resumptions dispatched while a spin-lock is held.

	A dispatcher may run a dispatched object inline: `haxe.coro.dispatchers.SelfDispatcher` always
	does, and `TrampolineDispatcher` does when no trampoline is running on the calling thread (e.g.
	when called from a plain thread or a non-coroutine callback). If the resumed code then takes the
	same lock, it spins forever on that thread.

	Actually deadlocking would hang the test run, so these tests instead check the lock state each
	time something is dispatched, through `ProbeDispatcher`, and count the dispatches that happen
	while the lock is held. The tests run on a trampoline, so nothing runs inline and nothing hangs.

	None of the setups in `hxcoro.run.Setup` deadlock on this by themselves: a running trampoline
	queues the resumption, and a thread pool resumes it on another thread, which only spins until
	the lock is released. The deadlock needs `SelfDispatcher`, or a `TrampolineDispatcher` entered
	from a thread with no running trampoline, e.g. `close()` called from a foreign thread.
**/
class TestLockedDispatch extends atest.Test {
	static function run<T>(dispatcher:ProbeDispatcher, scheduler:VirtualTimeScheduler, lambda:NodeLambda<T>):ICoroTask<T> {
		final task = CoroRun.with(dispatcher).createTask(lambda);
		task.start();
		var time = 0;
		while (task.isActive() && time < 1000) {
			scheduler.advanceBy(1);
			time++;
		}
		return task;
	}

	static function create() {
		final scheduler = new VirtualTimeScheduler();
		return {scheduler: scheduler, dispatcher: new ProbeDispatcher(new TrampolineDispatcher(scheduler))};
	}

	/**
		P2: bounded `close()` resumes waiters while the channel is locked.

		`src/hxcoro/ds/channels/bounded/BoundedWriter.hx:166-196`: under `Locked`, the `Open` case
		pops the waiters and calls `cont.succeedAsync(false)`, and only then stores `Closed`/`Draining`.
		The reader's `WaitContinuation.resume` (`BoundedReader.hx:15-36`) calls `state.lock()`, so with
		inline dispatch it spins on the lock that `close()` holds on the same thread. Real repro: a
		trampoline setup, a reader suspended in `read()`, and `close()` from `Thread.create` or from a
		plain non-coroutine callback.

		Fix: collect the waiters into a local array under the lock, store the final state (`Closed` if
		the buffer is empty, else `Draining`), and resume the waiters after unlocking.
		`tryWrite`/`tryRead` already resume outside the lock.
	**/
	function testBoundedCloseResumesReadersOutsideLock() {
		final env = create();
		var lockedDispatches = 0;
		final task = run(env.dispatcher, env.scheduler, node -> {
			final ch = Channel.createBounded({size: 1});
			final writer:BoundedWriter<Int> = cast ch.writer;
			final reader = node.async(_ -> ch.waitForRead());
			yield(); // the reader suspends on the empty channel
			env.dispatcher.probe = () -> if (@:privateAccess writer.state.load() == Locked) lockedDispatches++;
			ch.close();
			env.dispatcher.probe = null;
			reader.await();
		});
		Assert.isFalse(task.isActive());
		Assert.equals(0, lockedDispatches);
	}

	/**
		P2: same as above for a writer suspended on a full channel.
	**/
	function testBoundedCloseResumesWritersOutsideLock() {
		final env = create();
		var lockedDispatches = 0;
		final task = run(env.dispatcher, env.scheduler, node -> {
			final ch = Channel.createBounded({size: 1});
			final writer:BoundedWriter<Int> = cast ch.writer;
			ch.write(0);
			final waiter = node.async(_ -> ch.waitForWrite());
			yield(); // the writer suspends on the full channel
			env.dispatcher.probe = () -> if (@:privateAccess writer.state.load() == Locked) lockedDispatches++;
			ch.close();
			env.dispatcher.probe = null;
			waiter.await();
		});
		Assert.isFalse(task.isActive());
		Assert.equals(0, lockedDispatches);
	}
}
