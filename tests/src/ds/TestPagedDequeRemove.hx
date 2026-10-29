package ds;

import hxcoro.ds.PagedDeque;

/**
	Tests for `PagedDeque.remove` that run against whichever implementation is compiled. CI
	runs the main suite both without and with `-D use-vec-deque`, so both are covered.

	The channels, `CoroSemaphore` and `CoroLatch` call `remove` when a waiter is cancelled,
	and that waiter may already have been popped, so `remove` must only ever find live items.
**/
class TestPagedDequeRemove extends atest.Test {
	/**
		A popped element must not be found by `remove`, even after its page was reused.
	**/
	function testRemoveDoesNotFindPoppedElements() {
		final d = new PagedDeque<String>();
		final handles = [for (x in ["a", "b", "c", "d", "e", "f", "g", "h"]) d.push(x)];
		for (_ in 0...8) {
			d.pop();
		}
		d.push("x");
		Assert.isFalse(d.remove(handles[2], "c"), "removed an element that was already popped");
		Assert.isFalse(d.isEmpty(), "the live element was lost");
	}

	/**
		`remove` must remove the element it is given, not whatever is at the position `push`
		reported, which shifts as elements are popped.
	**/
	function testRemoveRemovesTheRightElement() {
		final d = new PagedDeque<String>();
		d.push("a");
		final handleB = d.push("b");
		d.pop();
		d.push("c");
		Assert.isTrue(d.remove(handleB, "b"));
		Assert.isFalse(d.isEmpty());
		Assert.equals("c", d.pop(), "removed the wrong element");
	}

	/**
		Like `testRemoveDoesNotFindPoppedElements`, for every page boundary and wrap-around
		position up to a few pages.
	**/
	function testRemoveDoesNotFindPoppedElementsAtAnyPosition() {
		for (k in 0...40) {
			final d = new PagedDeque<String>();
			final values = [for (i in 0...k) 'v$i'];
			final handles = [for (v in values) d.push(v)];
			for (_ in 0...k) {
				d.pop();
			}
			d.push("x");
			for (i in 0...k) {
				if (d.remove(handles[i], values[i])) {
					Assert.fail('after $k pops: removed ${values[i]}, which was already popped');
					return;
				}
			}
			if (d.isEmpty() || d.pop() != "x" || !d.isEmpty()) {
				Assert.fail('after $k pops: lost the live element');
				return;
			}
		}
		Assert.pass();
	}

	/**
		Removing the front element must work when it sits in the last slot of the storage, which
		the VecDeque implementation got wrong.
	**/
	function testRemoveFrontAtAnyPosition() {
		for (k in 0...40) {
			final d = new PagedDeque<String>();
			for (i in 0...k) {
				d.push('v$i');
			}
			for (_ in 0...k) {
				d.pop();
			}
			final handleX = d.push("x");
			d.push("y");
			if (!d.remove(handleX, "x")) {
				Assert.fail('after $k pops: could not remove the front element');
				return;
			}
			if (d.isEmpty() || d.pop() != "y" || !d.isEmpty()) {
				Assert.fail('after $k pops: the queue is broken after removing the front element');
				return;
			}
		}
		Assert.pass();
	}

	/**
		Removes every third element across several pages, at different start offsets, and checks
		that the rest comes out in order.
	**/
	function testRemoveLiveElementsAcrossPages() {
		for (offset in 0...20) {
			final d = new PagedDeque<String>();
			for (_ in 0...offset) {
				d.push("filler");
			}
			for (_ in 0...offset) {
				d.pop();
			}
			final values = [for (i in 0...30) 'v$i'];
			final handles = [for (v in values) d.push(v)];
			final expected = [];
			for (i in 0...values.length) {
				if (i % 3 == 1) {
					if (!d.remove(handles[i], values[i])) {
						Assert.fail('offset $offset: could not remove ${values[i]}');
						return;
					}
				} else {
					expected.push(values[i]);
				}
			}
			final actual = [];
			while (!d.isEmpty()) {
				actual.push(d.pop());
			}
			if (expected.join(",") != actual.join(",")) {
				Assert.fail('offset $offset: expected $expected, got $actual');
				return;
			}
		}
		Assert.pass();
	}
}
