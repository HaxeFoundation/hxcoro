package concurrent;

import haxe.ds.Vector;
import hxcoro.concurrent.CoroLatch;

class TestLatch extends atest.Test {
	function testCppSample() {
		final numTasks = 3;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		final workVector = new Vector(numTasks);
		final cleanUpVector = new Vector(numTasks);

		run(node -> {
			final startWork = new CoroLatch(1);
			final workerDone = new CoroLatch(numTasks);
			final startCleanUp = new CoroLatch(1);

			for (i in 0...numTasks) {
				node.async(node -> {
					startWork.wait();
					workVector[i] = '$i worked';
					workerDone.arriveAndWait(1);
					startCleanUp.wait();
					cleanUpVector[i] = '$i cleaned';
				});
			}

			log("Work is starting");
			startWork.arrive(1);
			workerDone.wait();
			log("Work is done");

			for (i in 0...numTasks) {
				log(workVector[i]);
				Assert.equals(null, cleanUpVector[i]);
			}

			startCleanUp.arrive(1);
			log("CleanUp has started");
			node.awaitChildren();
			log("CleanUp is done");

			for (i in 0...numTasks) {
				log(cleanUpVector[i]);
			}
		});

		Assert.same([
			"Work is starting",
			"Work is done",
			"0 worked",
			"1 worked",
			"2 worked",
			"CleanUp has started",
			"CleanUp is done",
			"0 cleaned",
			"1 cleaned",
			"2 cleaned"
		], actual);
	}

	static function hasWaiters(latch:CoroLatchImpl) {
		final deque = @:privateAccess latch.deque;
		return deque != null && !deque.isEmpty();
	}

	function testTimedOutWaitersAreRemoved() {
		var numTimeouts = 0;
		var waitersLeft = true;
		final latch = new CoroLatch(1);
		final task = VirtualRun.run(node -> {
			for (_ in 0...100) {
				try {
					timeout(1, _ -> latch.wait());
				} catch (e:hxcoro.exceptions.TimeoutException) {
					numTimeouts++;
				}
			}
			waitersLeft = hasWaiters(cast latch);
		});
		Assert.isFalse(task.isActive());
		Assert.equals(100, numTimeouts);
		Assert.isFalse(waitersLeft, "the timed out waiters were kept in the latch");
	}

	function testRemainingWaitersResumedAfterCancellation() {
		final lines = [];
		final task = VirtualRun.run(node -> {
			final latch = new CoroLatch(1);
			final waiter1 = node.async(_ -> {
				latch.wait();
				lines.push("1 resumed");
			});
			node.async(_ -> {
				latch.wait();
				lines.push("2 resumed");
			});
			yield(); // both waiters suspend in wait
			waiter1.cancel();
			latch.arrive(1);
		});
		Assert.isFalse(task.isActive());
		Assert.same(["2 resumed"], lines);
	}

	function testCancelWaitersWhileOpening() {
		final numTasks = 1000;
		run(node -> {
			final latch = new CoroLatch(1);
			final waiters = [
				for (_ in 0...numTasks) {
					node.async(_ -> {
						latch.wait();
					});
				}
			];
			delay(10); // let the waiters suspend in wait
			node.async(_ -> latch.arrive(1));
			// Races with the latch resuming its waiters
			for (i in 0...numTasks) {
				if (i & 1 == 1) {
					waiters[i].cancel();
				}
			}
		});
		// termination is test result
		Assert.pass();
	}
}