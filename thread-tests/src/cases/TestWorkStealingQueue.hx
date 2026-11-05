package cases;

import hxcoro.thread.WorkStealingQueue;

class TestWorkStealingQueue extends atest.Test {
	// Read as `Dynamic`, because on the JVM the storage of a type parameter is an `Object[]`.
	static function slot(queue:WorkStealingQueue<Array<Int>>, i:Int):Dynamic {
		final slots:haxe.ds.Vector<Dynamic> = cast @:privateAccess queue.storage.load().slots;
		return slots[i & (slots.length - 1)];
	}

	/**
		Stolen values used to stay in their slots until the producer wrapped around to them, so a
		queue kept the continuations of its last burst of work alive.
	**/
	function testAddClearsStolenSlots() {
		final queue = new WorkStealingQueue<Array<Int>>();
		for (i in 0...3) {
			queue.add([i]);
		}
		for (_ in 0...3) {
			queue.steal();
		}
		queue.add([3]);
		for (i in 0...3) {
			Assert.isNull(slot(queue, i), 'slot $i kept its stolen value');
		}
		Assert.notNull(slot(queue, 3));
	}

	function testLiveValuesSurviveWrapAround() {
		final queue = new WorkStealingQueue<Array<Int>>();
		var next = 0;
		var expected = 0;
		// Fill the 16 slots, steal most of them, then add enough to wrap around several times,
		// stealing in between, so that clearing runs across the wrap.
		for (round in 0...20) {
			for (_ in 0...(round == 0 ? 16 : 7)) {
				queue.add([next++]);
			}
			for (_ in 0...(round == 0 ? 10 : 7)) {
				final v = queue.steal();
				Assert.notNull(v);
				Assert.equals(expected++, v[0]);
			}
		}
		while (true) {
			final v = queue.steal();
			if (v == null) {
				break;
			}
			Assert.equals(expected++, v[0]);
		}
		Assert.equals(next, expected);
	}

	function testResizeKeepsValues() {
		final queue = new WorkStealingQueue<Array<Int>>();
		for (i in 0...5) {
			queue.add([i]);
		}
		queue.steal();
		queue.steal();
		// Grows the storage beyond 16 slots.
		for (i in 5...40) {
			queue.add([i]);
		}
		for (i in 2...40) {
			Assert.equals(i, queue.steal()[0]);
		}
		Assert.isNull(queue.steal());
	}
}
