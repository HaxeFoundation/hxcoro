package hxcoro.ds;

#if use_vec_deque

import haxe.ds.VecDeque;

/**
	A FIFO queue, implemented on top of `haxe.ds.VecDeque` when `use_vec_deque` is defined.
**/
@:forward.new
abstract PagedDeque<T>(VecDeque<T>) {
	/**
		Returns `true` if the queue contains no items.
	**/
	public inline function isEmpty() {
		return this.length == 0;
	}

	/**
		Adds `x` to the back of the queue.
	**/
	public inline function push(x:T) {
		return this.pushBack(x);
	}

	/**
		Removes and returns the item at the front of the queue.
	**/
	public inline function pop() {
		return this.popFront();
	}

	/**
		If the queue is not empty, stores the most recently pushed item in `out` without
		removing it and returns `true`. Otherwise, returns `false`.
	**/
	public function tryPeek(out:Out<T>) {
		final value = this.peekBack();
		if (value == null) {
			return false;
		}
		out.set(value);
		return true;
	}

	/**
		If the queue is not empty, removes the item at the front, stores it in `out` and
		returns `true`. Otherwise, returns `false`.
	**/
	public function tryPop(out:Out<T>) {
		if (isEmpty()) {
			return false;
		}
		@:nullSafety(Off) out.set(this.popFront());
		return true;
	}

	/**
		Removes `value` from the queue. Returns `true` if it was found, and `false` if it is no
		longer in the queue, e.g. because it was popped already.

		`handle` is what `push` returned for `value`. It is not used: positions shift as items
		are popped or removed, so the item is looked up by value instead.
	**/
	public function remove(handle:Int, value:T) {
		final index = this.indexOf(value);
		if (index < 0) {
			return false;
		}
		this.removeAt(index);
		return true;
	}
}

#else

import haxe.ds.Vector;
import haxe.Exception;
import hxcoro.ds.Out;

/**
	A fixed-size page of storage used by `PagedDeque`.
**/
class Page<T> {
	/**
		The storage of this page.
	**/
	public final data:Vector<T>;
	/**
		The number of items that were removed from the middle of this page.
	**/
	public var numDeleted:Int;
	/**
		The next page in the deque, if any.
	**/
	public var next:Null<Page<T>>;

	public function new(size:Int) {
		this.data = new Vector(size);
		numDeleted = 0;
	}

	/**
		Removes the first occurrence of `element` in the slots from `startIndex` to `endIndex`
		(exclusive), returning `true` if it was found.
	**/
	public function removeFrom(element:T, startIndex:Int, endIndex:Int) {
		for (i in startIndex...endIndex) {
			if (data[i] == element) {
				blitAt(i);
				++numDeleted;
				return true;
			}
		}
		return false;
	}

	/**
		Returns the item at `index` and clears its slot, so that the page neither keeps it alive
		nor finds it in a later `removeFrom`.
	**/
	@:nullSafety(Off)
	public inline function take(index:Int):T {
		final value = data[index];
		data[index] = null;
		return value;
	}

	/**
		Clears the deletion count and the link to the next page so the page can be reused.
	**/
	public function reset() {
		numDeleted = 0;
		next = null;
	}

	/**
		Returns the number of usable slots, which is the page size minus `numDeleted`.
	**/
	public inline function freeSpace() {
		return data.length - numDeleted;
	}

	@:nullSafety(Off)
	function blitAt(index:Int) {
		final end = freeSpace();
		final toBlit = end - index - 1;
		if (toBlit > 0) {
			Vector.blit(data, index + 1, data, index, toBlit);
		}
		// The last slot was moved one to the left, don't leave a copy behind.
		data[end - 1] = null;
	}
}

/**
	A FIFO queue which is not thread-safe, stored as a linked list of fixed-size pages that are reused once consumed.

	Items can be removed from the middle of the queue via `remove`, using the page returned by `push`.
**/
class PagedDeque<T> {
	final vectorSize:Int;
	var currentPage:Page<T>;
	var currentIndex:Int;
	var lastPage:Page<T>;
	var lastIndex(default, null):Int;

	public function new(vectorSize = 8) {
		this.vectorSize = vectorSize;
		currentPage = new Page(vectorSize);
		currentIndex = 0;
		lastPage = currentPage;
		lastIndex = 0;
	}

	inline function getPageDataAt<T>(page:Page<T>, index:Int) {
		return page.data[index];
	}

	inline function setPageDataAt<T>(page:Page<T>, index:Int, value:T) {
		page.data[index - page.numDeleted] = value;
	}

	// The `@:nullSafety(Off)` markers in this class were added because this implementation was
	// never compiled with null safety (the test suite only used `use_vec_deque`). The page
	// traversal relies on `next` being set for every page before `lastPage`.

	/**
		Calls `f` on each item in the queue, from front to back.
	**/
	@:nullSafety(Off)
	public function forEach(f:T->Void) {
		var currentPage = currentPage;
		var currentIndex = currentIndex;
		while (currentPage != lastPage) {
			while (currentIndex < currentPage.freeSpace()) {
				f(getPageDataAt(currentPage, currentIndex++));
			}
			currentIndex = 0;
			currentPage = currentPage.next;
		}
		while (currentIndex < lastIndex - currentPage.numDeleted) {
			f(getPageDataAt(currentPage, currentIndex++));
		}
	}

	/**
		Replaces each item in the queue with the result of calling `f` on it.
	**/
	@:nullSafety(Off)
	public function mapInPlace(f:T->T) {
		var currentPage = currentPage;
		var currentIndex = currentIndex;
		while (currentPage != lastPage) {
			while (currentIndex < currentPage.freeSpace()) {
				setPageDataAt(currentPage, currentIndex, f(getPageDataAt(currentPage, currentIndex++)));
			}
			currentIndex = 0;
			currentPage = currentPage.next;
		}
		while (currentIndex < lastIndex) {
			setPageDataAt(currentPage, currentIndex, f(getPageDataAt(currentPage, currentIndex++)));
		}
	}

	/**
		Combines the items in the queue from front to back using `f`, starting with `acc`.
	**/
	@:nullSafety(Off)
	public function fold<A>(acc:A, f:(acc:A, elt:T) -> A) {
		var currentPage = currentPage;
		var currentIndex = currentIndex;
		while (currentPage != lastPage) {
			while (currentIndex < currentPage.freeSpace()) {
				acc = f(acc, getPageDataAt(currentPage, currentIndex++));
			}
			currentIndex = 0;
			currentPage = currentPage.next;
		}
		while (currentIndex < lastIndex) {
			acc = f(acc, getPageDataAt(currentPage, currentIndex++));
		}
		return acc;
	}

	/**
		Adds `x` to the back of the queue and returns the page it was stored in.
	**/
	public function push(x:T) {
		if (lastIndex == lastPage.freeSpace()) {
			// current page is full
			if (lastPage.next == null) {
				// we have no next page, allocate one
				lastPage.next = new Page(vectorSize);
			}
			lastPage = lastPage.next;
			lastPage.reset();
			lastIndex = 1;
			setPageDataAt(lastPage, 0, x);
			return lastPage;
		}
		setPageDataAt(lastPage, lastIndex++, x);
		return lastPage;
	}

	/**
		Removes and returns the item at the front of the queue. Throws an exception if the queue is empty.
	**/
	public function pop() {
		if (skipConsumedPages()) {
			throw new Exception("pop() was called on empty PagedDeque");
		}
		final value = currentPage.take(currentIndex++);
		// If that consumed the current page, recycle it now so that `push` can reuse it.
		skipConsumedPages();
		return value;
	}

	/**
		Removes `element` from `page`, which should be the page returned by the `push` call that
		added it. Returns `true` if it was found, and `false` if it is no longer in the queue,
		e.g. because it was popped already.
	**/
	public function remove(page:Page<T>, element:T) {
		// Only search the live part of the page. Popped slots are cleared, but this also keeps
		// the search short on the first and last page.
		final startIndex = page == currentPage ? currentIndex : 0;
		final endIndex = page == lastPage ? lastIndex - page.numDeleted : page.freeSpace();
		final wasRemoved = page.removeFrom(element, startIndex, endIndex);
		if (wasRemoved && page == lastPage) {
			--lastIndex;
			--page.numDeleted;
		}
		return wasRemoved;
	}

	/**
		If the queue is not empty, removes the item at the front, stores it in `out` and
		returns `true`. Otherwise, returns `false`.
	**/
	public function tryPop(out:Out<T>) {
		if (isEmpty()) {
			return false;
		}
		out.set(pop());
		return true;
	}

	/**
		If the queue is not empty, stores the most recently pushed item in `out` without
		removing it and returns `true`. Otherwise, returns `false`.
	**/
	public function tryPeek(out:Out<T>) {
		if (isEmpty()) {
			return false;
		}

		out.set(getPageDataAt(lastPage, lastIndex - 1));

		return true;
	}

	/**
		Returns `true` if the queue contains no items. Does not modify the queue.
	**/
	public function isEmpty() {
		var page = currentPage;
		var index = currentIndex;
		while (true) {
			final endIndex = page == lastPage ? lastIndex - page.numDeleted : page.freeSpace();
			if (index < endIndex) {
				return false;
			}
			final next = page.next;
			if (page == lastPage || next == null) {
				return true;
			}
			// Pages before `lastPage` can be consumed or emptied by `remove`.
			page = next;
			index = 0;
		}
	}

	/**
		Moves `currentPage` past pages that were consumed, recycling them as the spare page after
		`lastPage`, and resets the indices once all pages are consumed so that `push` reuses the
		page. Returns `true` if the queue is empty.
	**/
	@:nullSafety(Off)
	function skipConsumedPages() {
		while (currentIndex == currentPage.freeSpace()) {
			if (currentPage == lastPage) {
				resetCurrent();
				return true;
			}
			final consumed = currentPage;
			currentPage = consumed.next;
			currentIndex = 0;
			if (lastPage.next == null) {
				consumed.reset();
				lastPage.next = consumed;
			}
		}

		return currentPage == lastPage && currentIndex == lastIndex - currentPage.numDeleted;
	}

	function resetCurrent() {
		currentIndex = 0;
		lastIndex = 0;
		currentPage.reset();
	}
}

#end