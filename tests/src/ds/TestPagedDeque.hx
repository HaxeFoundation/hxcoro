package ds;

import haxe.ds.ArraySort;
import hxcoro.ds.PagedDeque;

/**
	The tests at the top only use the API that both implementations share, so they run in both
	builds (CI runs eval with and without `-D use-vec-deque`). The tests in the `#if` block
	inspect the pages of the default implementation.
**/
class TestPagedDeque extends atest.Test {
	// The channels, `CoroSemaphore` and `CoroLatch` call `remove` when a waiter is cancelled,
	// and that waiter may already have been popped, so `remove` must only ever find live items.

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

	#if !use_vec_deque
	public function test() {
		function expect(expected:Array<Any>, d:Page<Any>, ?pos:haxe.PosInfos) {
			final actual:Array<Any> = [for (x in d.data) x];
			Assert.same(expected, actual, null, pos);
		}

		var d:PagedDeque<Any> = new PagedDeque(9);
		d.push(0);
		d.push(1);
		d.push(2);
		d.push(3);
		final page = d.push(4);
		final nnull = #if cpp 0 #else null #end; // I don't get it though
		expect([0, 1, 2, 3, 4, nnull, nnull, nnull, nnull], page);
		// delete non-existing
		Assert.isFalse(d.remove(page, 5));
		Assert.isFalse(d.isEmpty());
		expect([0, 1, 2, 3, 4, nnull, nnull, nnull, nnull], page);
		// delete first
		Assert.isTrue(d.remove(page, 0));
		Assert.isFalse(d.isEmpty());
		expect([1, 2, 3, 4, nnull, nnull, nnull, nnull, nnull], page);
		// delete last
		Assert.isTrue(d.remove(page, 4));
		Assert.isFalse(d.isEmpty());
		expect([1, 2, 3, nnull, nnull, nnull, nnull, nnull, nnull], page);
		// delete middle
		Assert.isTrue(d.remove(page, 2));
		Assert.isFalse(d.isEmpty());
		expect([1, 3, nnull, nnull, nnull, nnull, nnull, nnull, nnull], page);
		// push afterwards
		d.push(5);
		Assert.isFalse(d.isEmpty());
		expect([1, 3, 5, nnull, nnull, nnull, nnull, nnull, nnull], page);
		// drain
		Assert.isTrue(d.remove(page, 1));
		Assert.isTrue(d.remove(page, 3));
		Assert.isTrue(d.remove(page, 5));
		Assert.isTrue(d.isEmpty());
		// push after empty
		d.push(6);
		Assert.isFalse(d.isEmpty());
		Assert.equals(6, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	function createTwoPageDeck(pageSize:Int) {
		var d:PagedDeque<Any> = new PagedDeque(pageSize);
		final pages = [
			for (i in 0...pageSize << 1) {
				d.push(i);
			}
		];
		return {
			deque: d,
			pages: pages
		}
	}

	public function testBounds1() {
		final data = createTwoPageDeck(1);
		final pages = data.pages;
		final d = data.deque;
		Assert.notEquals(pages[0], pages[1]);
		Assert.isFalse(d.remove(pages[0], 1));
		Assert.isFalse(d.remove(pages[1], 0));
		// delete last, then push
		Assert.isTrue(d.remove(pages[1], 1));
		d.push(2);
		Assert.equals(0, d.pop());
		Assert.equals(2, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testBounds2() {
		final data = createTwoPageDeck(2);
		final pages = data.pages;
		final d = data.deque;
		Assert.equals(pages[0], pages[1]);
		Assert.equals(pages[2], pages[3]);
		Assert.notEquals(pages[0], pages[2]);
		Assert.isFalse(d.remove(pages[0], 2));
		Assert.isFalse(d.remove(pages[0], 3));
		Assert.isFalse(d.remove(pages[2], 0));
		Assert.isFalse(d.remove(pages[2], 1));
		// delete first and last
		Assert.isTrue(d.remove(pages[0], 0));
		Assert.isTrue(d.remove(pages[2], 3));
		Assert.equals(1, d.pop());
		Assert.equals(2, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testBounds3() {
		final data = createTwoPageDeck(3);
		final pages = data.pages;
		final d = data.deque;
		// delete middle
		Assert.isTrue(d.remove(pages[0], 1));
		Assert.isTrue(d.remove(pages[3], 4));
		Assert.equals(0, d.pop());
		Assert.equals(2, d.pop());
		Assert.equals(3, d.pop());
		Assert.equals(5, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testWildDeletion() {
		final data = createTwoPageDeck(100);
		final pages = data.pages;
		final page1 = pages[0];
		final page2 = pages[100];
		final d = data.deque;
		final values = [for (i in 0...200) i];
		ArraySort.sort(values, (_, _) -> Math.random() > 0.5 ? 1 : -1);
		Assert.isFalse(d.isEmpty());
		for (i in values) {
			switch [d.remove(page1, i), d.remove(page2, i)] {
				case [true, false] | [false, true]:
				case [true, true]:
					Assert.fail('Deleted $i from two pages');
				case [false, false]:
					Assert.fail('Couldn\'t delete $i from any page');
			}
		}
		Assert.isTrue(d.isEmpty());
	}

	public function testDeleteDelete() {
		// delete + delete
		final d = new PagedDeque(1);
		final page1 = d.push(1);
		final page2 = d.push(2);
		Assert.isTrue(d.remove(page1, 1));
		Assert.isTrue(d.remove(page2, 2));
		Assert.isTrue(d.isEmpty());
		// again
		final page1 = d.push(1);
		final page2 = d.push(2);
		Assert.isTrue(d.remove(page1, 1));
		Assert.isTrue(d.remove(page2, 2));
		Assert.isTrue(d.isEmpty());
	}

	public function testDeletePop() {
		// delete + pop
		final d = new PagedDeque(1);
		final page1 = d.push(1);
		d.push(2);
		Assert.isTrue(d.remove(page1, 1));
		Assert.equals(2, d.pop());
		Assert.isTrue(d.isEmpty());
		// again
		final page1 = d.push(1);
		d.push(2);
		Assert.isTrue(d.remove(page1, 1));
		Assert.equals(2, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testPopDelete() {
		// delete + pop
		final d = new PagedDeque(1);
		d.push(1);
		final page1 = d.push(2);
		Assert.equals(1, d.pop());
		Assert.isTrue(d.remove(page1, 2));
		Assert.isTrue(d.isEmpty());
		// again
		d.push(1);
		final page1 = d.push(2);
		Assert.equals(1, d.pop());
		Assert.isTrue(d.remove(page1, 2));
		Assert.isTrue(d.isEmpty());
	}

	public function testDeleteAfterPopOnCurrent() {
		final d = new PagedDeque(4);
		final page = d.push(1);
		d.push(2);
		Assert.equals(1, d.pop());
		Assert.equals(2, d.pop());
		Assert.isTrue(d.isEmpty());
		Assert.isFalse(d.remove(page, 1));
		Assert.isFalse(d.remove(page, 2));
		Assert.isTrue(d.isEmpty());
		d.push(3);
		Assert.isFalse(d.isEmpty());
		d.push(4);
		Assert.isFalse(d.isEmpty());
		Assert.equals(3, d.pop());
		Assert.isFalse(d.isEmpty());
		Assert.equals(4, d.pop());
		Assert.isTrue(d.isEmpty());
		final page2 = d.push(5);
		Assert.isTrue(page == page2); // assert page reuse
		Assert.isFalse(d.isEmpty());
		Assert.equals(5, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testDeleteMiddlePage() {
		final d = new PagedDeque(2);
		final pages = [
			for (i in 0...6) {
				d.push(i);
			}
		];
		final middlePage = pages[2];
		d.remove(middlePage, 2);
		d.remove(middlePage, 3);
		Assert.equals(0, d.pop());
		Assert.isFalse(d.isEmpty());
		Assert.equals(1, d.pop());
		Assert.isFalse(d.isEmpty());
		Assert.equals(4, d.pop());
		Assert.isFalse(d.isEmpty());
		Assert.equals(5, d.pop());
		Assert.isTrue(d.isEmpty());
	}

	public function testDeleteLastPageThenPushTwice() {
		final pd = new PagedDeque(1);
		final page = pd.push(1);
		Assert.isTrue(pd.remove(page, 1));
		Assert.equals(page, pd.push(2));
		Assert.notEquals(page, pd.push(3));
	}
	#end
}