package schedulers;

import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import hxcoro.schedulers.MinimumHeap;
import hxcoro.schedulers.ScheduledEvent;

class TestMinimumHeap extends atest.Test {
	static function event(runTime:Int) {
		return new ScheduledEvent(new FunctionContinuation(Context.empty, (_, _) -> {}), runTime);
	}

	/**
		Extracts all events and checks that they come out ordered by due time, and in insertion
		order among events with the same due time.
	**/
	static function checkOrder(heap:MinimumHeap, inserted:Array<ScheduledEvent>, label:String) {
		var previous:Null<ScheduledEvent> = null;
		var count = 0;
		while (true) {
			final e = heap.extract();
			if (e == null) {
				break;
			}
			count++;
			if (previous != null) {
				if (e.runTime < previous.runTime) {
					Assert.fail('$label: ${e.runTime} came out after ${previous.runTime}');
					return;
				}
				if (e.runTime == previous.runTime && inserted.indexOf(e) < inserted.indexOf(previous)) {
					Assert.fail('$label: events with due time ${e.runTime} came out of insertion order');
					return;
				}
			}
			previous = e;
		}
		Assert.equals(inserted.length, count, '$label: wrong number of events');
	}

	function testSameDueTimeIsFifo() {
		final heap = new MinimumHeap();
		final inserted = [for (_ in 0...100) event(5)];
		for (e in inserted) {
			heap.insert(e);
		}
		for (e in inserted) {
			if (heap.extract() != e) {
				Assert.fail("events with the same due time came out of insertion order");
				return;
			}
		}
		Assert.isTrue(heap.isEmpty());
	}

	function testRandomDueTimes() {
		for (round in 0...20) {
			final heap = new MinimumHeap();
			// Few distinct due times, so that many events share one.
			final inserted = [for (_ in 0...200) event(Std.random(10))];
			for (e in inserted) {
				heap.insert(e);
			}
			final before = Assert.assertions.load();
			checkOrder(heap, inserted, 'round $round');
			if (Assert.assertions.load() != before + 1) {
				return;
			}
		}
	}

	/**
		Inserting while extracting, as the schedulers do, keeps the order among the events that
		are in the heap at the same time.
	**/
	function testInterleavedInsertAndExtract() {
		final heap = new MinimumHeap();
		final inserted = [];
		var lastExtracted:Null<ScheduledEvent> = null;
		for (i in 0...500) {
			// Never insert events before the last extracted one, as a scheduler wouldn't either.
			final e = event((lastExtracted == null ? 0 : Std.int(lastExtracted.runTime.low)) + Std.random(5));
			inserted.push(e);
			heap.insert(e);
			if (i % 3 == 0) {
				final extracted = heap.extract();
				if (lastExtracted != null && extracted != null && extracted.runTime < lastExtracted.runTime) {
					Assert.fail('${extracted.runTime} came out after ${lastExtracted.runTime}');
					return;
				}
				lastExtracted = extracted;
			}
		}
		final remaining = [];
		while (!heap.isEmpty()) {
			remaining.push(heap.extract());
		}
		for (i in 1...remaining.length) {
			final a = remaining[i - 1];
			final b = remaining[i];
			if (b.runTime < a.runTime || (b.runTime == a.runTime && inserted.indexOf(b) < inserted.indexOf(a))) {
				Assert.fail("the remaining events came out of order");
				return;
			}
		}
		Assert.pass();
	}

	function testExtractFromEmptyHeap() {
		final heap = new MinimumHeap();
		Assert.isNull(heap.extract());
		heap.insert(event(1));
		Assert.notNull(heap.extract());
		Assert.isNull(heap.extract());
		Assert.isTrue(heap.isEmpty());
	}
}
