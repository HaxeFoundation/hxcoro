package structured;

import hxcoro.concurrent.CoroLatch;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.exceptions.InvalidTaskStateException;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.task.AbstractTask;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;

/**
	`awaitChildren` resumes its waiter outside the children lock, and allows one waiter at a time.
**/
class TestAwaitChildren extends atest.Test {
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
		A dispatcher may run a dispatched object inline, e.g. `SelfDispatcher`, or a trampoline that
		is entered from a thread without a running trampoline. If the `awaitChildren` waiter were
		resumed while the children lock is held, such a resumption could take the same lock, e.g. by
		calling `node.async`, and spin forever. Here `ProbeDispatcher` records whether the lock is
		held at each dispatch instead of deadlocking.
	**/
	function testWaiterIsResumedOutsideLock() {
		final env = create();
		var lockedDispatches = 0;
		final task = run(env.dispatcher, env.scheduler, node -> {
			final self:AbstractTask = cast node;
			env.dispatcher.probe = () -> if (@:privateAccess self.numActiveChildren.load() == -1) lockedDispatches++;
			node.async(_ -> yield());
			node.awaitChildren();
			env.dispatcher.probe = null;
		});
		Assert.isFalse(task.isActive());
		Assert.equals(0, lockedDispatches);
	}

	function testWaiterWithoutChildrenIsResumedOutsideLock() {
		final env = create();
		var lockedDispatches = 0;
		final task = run(env.dispatcher, env.scheduler, node -> {
			final self:AbstractTask = cast node;
			env.dispatcher.probe = () -> if (@:privateAccess self.numActiveChildren.load() == -1) lockedDispatches++;
			node.awaitChildren();
			env.dispatcher.probe = null;
		});
		Assert.isFalse(task.isActive());
		Assert.equals(0, lockedDispatches);
	}

	/**
		`awaitChildren` is meant for the node's own coroutine. A second concurrent call, only possible
		through a node that was passed to another task, throws instead of silently replacing the first
		waiter, which then never woke up.
	**/
	function testSecondConcurrentCallThrows() {
		var firstWoken = false;
		var secondError:Null<haxe.Exception> = null;
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			var escaped:Null<CoroBaseTask<Any>> = null;
			node.async(n -> {
				escaped = cast n;
				n.async(_ -> latch.wait());
				n.awaitChildren();
				firstWoken = true;
			});
			yield();
			final second = node.async(_ -> escaped.awaitChildren());
			try {
				second.await();
			} catch (e:haxe.Exception) {
				secondError = e;
			}
			latch.arrive(1);
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(firstWoken, "the first waiter never woke up");
		Assert.isOfType(secondError, InvalidTaskStateException);
	}
}
