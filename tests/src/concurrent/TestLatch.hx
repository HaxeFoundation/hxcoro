package concurrent;

import haxe.ds.Vector;
import hxcoro.concurrent.CoroLatch;

class TestLatch extends utest.Test {
	function testCppSample() {
		final numTasks = 3;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		final workVector = new Vector(numTasks);
		final cleanUpVector = new Vector(numTasks);

		CoroRun.run(node -> {
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
}