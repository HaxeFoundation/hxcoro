package concurrent;

import haxe.exceptions.CoroutineException;
import haxe.ds.Vector;
import hxcoro.concurrent.CoroBarrier;

class TestBarrier extends atest.Test {
	function testCppSample() {
		final numTasks = 3;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		final workerVector = new Vector(numTasks);

		run(node -> {
			function onCompletion() {
				static var phase = "... done working";
				log(phase);
				for (message in workerVector) {
					log(message);
				}
				phase = "... done cleaning";
			}

			final syncPoint = new CoroBarrier(numTasks, onCompletion);

			for (i in 0...numTasks) {
				node.async(node -> {
					workerVector[i] = '$i worked';
					syncPoint.arriveAndWait();

					workerVector[i] = '$i cleaned';
					syncPoint.arriveAndWait();
				});
			}
		});

		Assert.same([
			"... done working",
			"0 worked",
			"1 worked",
			"2 worked",
			"... done cleaning",
			"0 cleaned",
			"1 cleaned",
			"2 cleaned"
		], actual);
	}

	function testUsableAfterCallbackThrows() {
		var shouldThrow = true;
		final barrier = new CoroBarrier(1, () -> {
			if (shouldThrow) {
				shouldThrow = false;
				throw new haxe.Exception("callback failure");
			}
		});
		Assert.raises(() -> barrier.arrive(1), haxe.Exception);
		// Check the counter directly because calling `arrive` on a locked barrier spins forever.
		final impl:hxcoro.concurrent.CoroLatch.CoroLatchImpl = cast barrier;
		Assert.equals(1, @:privateAccess impl.counter.load());
		barrier.arrive(1);
		Assert.pass();
	}

	function testWaitersResumedWhenCallbackThrows() {
		var resumed = false;
		var raised = false;
		final task = VirtualRun.run(node -> {
			final barrier = new CoroBarrier(2, () -> throw new haxe.Exception("callback failure"));
			node.async(_ -> {
				barrier.arriveAndWait();
				resumed = true;
			});
			yield(); // the waiter suspends in arriveAndWait
			try {
				barrier.arrive(1);
			} catch (e:haxe.Exception) {
				raised = true;
			}
		});
		Assert.isFalse(task.isActive());
		Assert.isTrue(raised);
		Assert.isTrue(resumed);
	}

	function testCancelledWaiterIsRemoved() {
		var waitersLeft = true;
		var completed = false;
		final task = VirtualRun.run(node -> {
			final barrier = new CoroBarrier(2);
			final waiter = node.async(_ -> barrier.arriveAndWait());
			yield(); // the waiter suspends in arriveAndWait
			waiter.cancel();
			delay(1);
			final impl:hxcoro.concurrent.CoroLatch.CoroLatchImpl = cast barrier;
			final deque = @:privateAccess impl.deque;
			waitersLeft = deque != null && !deque.isEmpty();
			// The cancelled waiter's arrival still counts, so this completes the phase.
			barrier.arriveAndWait();
			completed = true;
		});
		Assert.isFalse(task.isActive());
		Assert.isFalse(waitersLeft, "the cancelled waiter was kept in the barrier");
		Assert.isTrue(completed);
	}

	function testCancelWaitersWhileCompleting() {
		final numTasks = 1000;
		run(node -> {
			final barrier = new CoroBarrier(numTasks + 1);
			final waiters = [
				for (_ in 0...numTasks) {
					node.async(_ -> barrier.arriveAndWait());
				}
			];
			delay(10); // let the waiters suspend in arriveAndWait
			node.async(_ -> barrier.arrive(1));
			// Races with the barrier completing the phase and resuming its waiters
			for (i in 0...numTasks) {
				if (i & 1 == 1) {
					waiters[i].cancel();
				}
			}
		});
		// termination is test result
		Assert.pass();
	}

	function testArriveAndDrop() {
		final numTasks = 10;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		run(node -> {
			final syncPoint = new CoroBarrier(numTasks + 1);

			var numTasks = numTasks;
			while (numTasks > 0) {
				log("Iterating " + numTasks);
				for (i in 0...numTasks) {
					node.async(node -> {
						syncPoint.arriveAndWait();

						if (i == numTasks - 1) {
							log("Dropping " + i);
							syncPoint.arriveAndDrop();
						} else {
							syncPoint.arriveAndWait();
						}
					});
				}
				syncPoint.arriveAndWait();
				syncPoint.arriveAndWait();
				--numTasks;
			}
			syncPoint.arriveAndDrop();
			Assert.raises(() -> {
				syncPoint.arriveAndDrop();
			}, CoroutineException);
		});

		final expected = [];
		var numTasks = numTasks;
		while (numTasks > 0) {
			expected.push("Iterating " + numTasks);
			--numTasks;
			expected.push("Dropping " + numTasks);
		}
		Assert.same(expected, actual);
	}
}