package concurrent;

import haxe.exceptions.CoroutineException;
import haxe.ds.Vector;
import hxcoro.concurrent.CoroLatch;

class TestBarrier extends utest.Test {
	function testCppSample() {
		final numTasks = 3;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		final workerVector = new Vector(numTasks);

		CoroRun.run(node -> {
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

	function testArriveAndDrop() {
		final numTasks = 10;
		final actual = [];
		function log(msg:String) {
			actual.push(msg);
		}
		CoroRun.run(node -> {
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