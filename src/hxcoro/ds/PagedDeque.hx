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
		Removes the item at `index`. Returns `true` if an item was removed.
	**/
	public inline function remove(index:Int, value:T) {
		final removed = this.removeAt(index);
		return removed != null;
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
		Removes the first occurrence of `element` at or after `startIndex`, returning `true` if it was found.
	**/
	public function removeFrom(element:T, startIndex:Int) {
		for (i in startIndex...data.length - numDeleted) {
			if (data[i] == element) {
				blitAt(i);
				++numDeleted;
				return true;
			}
		}
		return false;
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

	function blitAt(index:Int) {
		final toBlit = freeSpace() - index - 1;
		if (toBlit > 0) {
			Vector.blit(data, index + 1, data, index, toBlit);
		}
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

	/**
		Calls `f` on each item in the queue, from front to back.
	**/
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
		if (currentIndex == currentPage.freeSpace()) {
			// end of page, need to swap
			var nextPage = currentPage.next;
			if (nextPage == null) {
				throw new Exception("pop() was called on empty PagedDeque");
			}
			if (lastPage.next == null) {
				// reuse current page as next last page
				lastPage.next = currentPage;
				currentPage.reset();
			}
			currentPage = nextPage;
			currentIndex = 1;
			return getPageDataAt(currentPage, 0);
		} else if (currentIndex == currentPage.freeSpace() - 1 && currentPage.next == null) {
			// deque is empty, reset to reuse current page
			resetCurrent();
			return getPageDataAt(currentPage, currentPage.freeSpace() - 1);
		} else {
			return getPageDataAt(currentPage, currentIndex++);
		}
	}

	/**
		Removes `element` from `page`, which should be the page returned by the `push` call that added it. Returns `true` if it was found.
	**/
	public function remove(page:Page<T>, element:T) {
		final wasRemoved = if (page == currentPage) {
			page.removeFrom(element, currentIndex);
		} else {
			page.removeFrom(element, 0);
		}
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
			// TODO: could probably integrate this better in the branches below
			return false;
		}
		if (currentIndex == vectorSize) {
			// end of page, need to swap
			var nextPage = currentPage.next;
			if (lastPage.next == null) {
				// reuse current page as next last page
				lastPage.next = currentPage;
				currentPage.reset();
			}
			currentPage = nextPage;
			currentIndex = 1;
			out.set(currentPage.data[0]);
			return true;
		} else if (currentIndex == vectorSize - 1 && currentPage.next == null) {
			// deque is empty, reset to reuse current page
			currentIndex = 0;
			lastIndex = 0;
			out.set(currentPage.data[vectorSize - 1]);
			return true;
		} else {
			out.set(currentPage.data[currentIndex++]);
			return true;
		}
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
		Returns `true` if the queue contains no items.
	**/
	public function isEmpty() {
		while (currentIndex == currentPage.freeSpace()) {
			if (currentPage.next == null || currentPage == lastPage) {
				resetCurrent();
				return true;
			}
			currentPage = currentPage.next;
			currentIndex = 0;
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