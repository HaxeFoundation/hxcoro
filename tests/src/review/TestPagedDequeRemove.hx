package review;

import hxcoro.ds.PagedDeque;

/**
	Known failures from the 1.0 review: `PagedDeque.remove`.

	These run against whichever implementation is compiled. CI runs the main suite both
	without and with `-D use-vec-deque`, so both implementations are covered.
**/
class TestPagedDequeRemove extends atest.Test {
	/**
		The paged implementation never clears popped slots, and `remove` scans the last page to
		its end instead of to the last live element. It therefore finds an element that was
		popped long ago and shifts a live element out of the queue.
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
		With `-D use-vec-deque`, `push` returns a storage index but `remove` treats it as a logical
		position, and the value is ignored. After a pop the wrong element is removed.
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
}
