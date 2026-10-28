package hxcoro.ds;

import haxe.ds.Vector;
import haxe.exceptions.ArgumentException;

/**
	A fixed-capacity circular buffer which is not thread-safe.

	Items are pushed at the head and can be removed from either end. The constructor
	throws `haxe.exceptions.ArgumentException` if `capacity` is less than 1.
**/
final class CircularBuffer<T> {
	final storage : Vector<T>;

	var head : Int;

	var tail : Int;

	public function new(capacity : Int) {
		if (capacity < 1) {
			throw new ArgumentException("capacity", "Capacity must be greater than zero");
		}

		// We need +1 since we do a "full" check by comparing the head and tail.
		storage = new Vector(capacity + 1);
		head    = 0;
		tail    = 0;
	}

	/**
		If the buffer is not full, adds `v` at the head and returns `true`. Otherwise,
		returns `false`.
	**/
	public function tryPush(v:T) {
		final nextHead = increment(head);

		return if (tail != nextHead) {
			storage[head] = v;
			head = nextHead;

			true;
		} else {
			false;
		}
	}

	/**
		If the buffer is not empty, stores the most recently pushed item in `out` without
		removing it and returns `true`. Otherwise, returns `false`.
	**/
	public function tryPeekHead(out:Out<T>) {
		if (wasEmpty()) {
			return false;
		}

		out.set(storage[decrement(head)]);

		return true;
	}

	/**
		If the buffer is not empty, removes the most recently pushed item, stores it in `out`
		and returns `true`. Otherwise, returns `false`.
	**/
	public function tryPopHead(out:Out<T>) {
		if (wasEmpty()) {
			return false;
		}

		head = decrement(head);

		out.set(storage[head]);

		return true;
	}

	/**
		If the buffer is not empty, removes the oldest item, stores it in `out` and returns
		`true`. Otherwise, returns `false`.
	**/
	public function tryPopTail(out:Out<T>) {
		if (wasEmpty()) {
			return false;
		}

		out.set(storage[tail]);

		tail = increment(tail);

		return true;
	}

	/**
		Returns `true` if the buffer contains no items.
	**/
	public function wasEmpty() {
		return head == tail;
	}

	/**
		Returns `true` if the buffer has reached its capacity.
	**/
	public function wasFull() {
		final nextHead = increment(head);

		return nextHead == tail;
	}

	inline function increment(v : Int) {
		return (v + 1) % storage.length;
	}

	inline function decrement(v : Int) {
		return if (v == 0) {
			storage.length - 1;
		} else {
			v - 1;
		}
	}
}