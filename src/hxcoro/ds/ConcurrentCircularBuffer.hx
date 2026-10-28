package hxcoro.ds;

import haxe.ds.Vector;
import haxe.exceptions.ArgumentException;
import haxe.atomic.AtomicInt;

/**
	A thread-safe FIFO circular buffer.

	It supports at most a single producer and a single consumer at any one time. The
	behaviour with multiple producers or consumers is undefined.
**/
final class ConcurrentCircularBuffer<T> {
	final storage : Vector<T>;

	final head : AtomicInt;

	final tail : AtomicInt;

	public function new(capacity : Int) {
		if (capacity < 1) {
			throw new ArgumentException("capacity", "Capacity must be greater than zero");
		}

		// We need +1 since we do a "full" check by comparing the head and tail.
		storage = new Vector(capacity + 1);
		head    = new AtomicInt(0);
		tail    = new AtomicInt(0);
	}

	/**
		If the buffer is not full, adds `v` at the end and returns `true`. Otherwise,
		returns `false`.
	**/
	public function tryPush(v : T) {
		final currentTail = tail.load();
		final nextTail    = increment(currentTail);

		if (nextTail != head.load()) {
			storage[currentTail] = v;
			tail.store(nextTail);
			return true;
		}

		return false;
	}

	/**
		If the buffer is not empty, removes the item at the beginning, stores it in `out`
		and returns `true`. Otherwise, returns `false`.
	**/
	public function tryPop(out : Out<T>) {
		final currentHead = head.load();
		if (currentHead == tail.load()) {
			return false;
		}

		// Note : We should probably wipe the previous value here to prevent references being kept to otherwise dead objects.
		// is it safe to do a `= null` even if the circular buffer is storing, say, ints?
		out.set(storage[currentHead]);

		head.store(increment(currentHead));

		return true;
	}

	/**
		Returns `true` if the buffer contains no items.
	**/
	public function wasEmpty() {
		return head.load() == tail.load();
	}

	/**
		Returns `true` if the buffer has reached its capacity.
	**/
	public function wasFull() {
		final nextTail = increment(tail.load());

		return nextTail == head.load();
	}

	inline function increment(v : Int) {
		return (v + 1) % storage.length;
	}
}