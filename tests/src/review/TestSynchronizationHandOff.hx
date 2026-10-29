package review;

import hxcoro.concurrent.CoroBarrier;
import hxcoro.concurrent.CoroMutex;
import hxcoro.concurrent.CoroSemaphore;

/**
	Known failures from the 1.0 review: semaphores, mutexes and barriers.
**/
class TestSynchronizationHandOff extends atest.Test {
	/**
		`release` hands the permit to the first waiter and only dispatches its resumption. If the
		waiter is cancelled before that runs, the cancellation wins, the resumption is dropped and
		the permit is never returned. With a mutex this means it stays locked forever. On a thread
		pool, a `timeout` around `acquire` that fires at the wrong moment is enough.
	**/
	function testMutexPermitNotLostWhenWaiterIsCancelled() {
		var unlocked = false;
		final task = VirtualRun.run(node -> {
			final m = new CoroMutex();
			m.acquire();
			final waiter = node.async(_ -> {
				m.acquire();
				m.release();
			});
			yield(); // the waiter suspends in acquire
			m.release(); // hands the permit to the waiter
			waiter.cancel(); // cancellation wins before the waiter resumes
			delay(1);
			unlocked = m.tryAcquire();
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(unlocked, "the mutex stayed locked after its only waiter was cancelled");
	}

	/**
		Same as above with a semaphore that has several permits.
	**/
	function testSemaphorePermitNotLostWhenWaiterIsCancelled() {
		var permits = 0;
		final task = VirtualRun.run(node -> {
			final s = new CoroSemaphore(2);
			s.acquire();
			s.acquire();
			final waiter = node.async(_ -> {
				s.acquire();
				s.release();
			});
			yield();
			s.release();
			waiter.cancel();
			delay(1);
			while (s.tryAcquire()) {
				permits++;
			}
		});
		Assert.isFalse(task.isActive());
		Assert.equals(1, permits, "a permit was lost");
	}

	/**
		The barrier callback runs while the counter is locked at -1. If it throws, the counter is
		never restored, and every later `arrive` or `wait` spins forever. This checks the counter
		directly because calling `arrive` again would hang the test.
	**/
	function testBarrierUsableAfterCallbackThrows() {
		final barrier = new CoroBarrier(1, () -> throw new haxe.Exception("callback failure"));
		try {
			barrier.arrive(1);
		} catch (_:Dynamic) {}
		final impl:hxcoro.concurrent.CoroLatch.CoroLatchImpl = cast barrier;
		Assert.notEquals(-1, @:privateAccess impl.counter.load(), "the barrier stays locked after its callback threw");
	}
}
