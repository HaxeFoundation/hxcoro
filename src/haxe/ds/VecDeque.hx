package haxe.ds;

import haxe.ds.Vector;

/**
	A double-ended queue implemented as a growable ring buffer.
**/
class VecDeque<T> {
	var storage:Vector<T>;
	var head:Int;

	public var length(default, null):Int;

	public function new() {
		storage = new Vector(0);
		head = 0;
		length = 0;
	}

	inline function capacity() {
		return storage.length;
	}

	inline function isFull() {
		return length == capacity();
	}

	inline function computeIndex(idx:Int) {
		if (head + idx >= capacity()) {
			return head + idx - capacity();
		} else {
			return head + idx;
		}
	}

	function grow() {
		var old_capacity = storage.length;
		var new_capacity = if (old_capacity == 0) {
			1;
		} else {
			old_capacity * 2;
		};
		var new_storage = new Vector(new_capacity);
		if (head + length < old_capacity) {
			Vector.blit(storage, head, new_storage, 0, length);
		} else {
			Vector.blit(storage, head, new_storage, 0, old_capacity - head);
			Vector.blit(storage, 0, new_storage, old_capacity - head, length - (old_capacity - head));
		}
		this.storage = new_storage;
		this.head = 0;
	}

	public function get(idx:Int):T {
		if (idx > length || idx < 0) {
			throw "out of bounds";
		}

		return storage[computeIndex(idx)];
	}

	public function set(idx:Int, value:T):T {
		if (idx > length || idx < 0) {
			throw "out of bounds";
		}

		return storage[computeIndex(idx)] = value;
	}

	public function indexOf(value:T):Int {
		for (i in 0...length) {
			if (storage[computeIndex(i)] == value) {
				return i;
			}
		}

		return -1;
	}

	public function peekBack() {
		if (length == 0) {
			return null;
		}
		return storage[computeIndex(length - 1)];
	}

	public function peekFront() {
		if (length == 0) {
			return null;
		}
		return storage[head];
	}

	public function pushBack(value:T) {
		if (isFull()) {
			grow();
		}

		final index = computeIndex(length++);
		storage[index] = value;
		return index;
	}

	public function pushFront(value:T) {
		if (isFull()) {
			grow();
		}

		if (head == 0) {
			head = capacity() - 1;
			length++;
		} else {
			head--;
			length++;
		}

		storage[head] = value;
		return head;
	}

	public function popBack():Null<T> {
		if (length == 0) {
			return null;
		} else {
			this.length--;
			final storage_idx = computeIndex(length);
			final value = storage[storage_idx];
			storage[storage_idx] = null;
			return value;
		}
	}

	public function popFront():Null<T> {
		if (length == 0) {
			return null;
		} else {
			var old_head = head;
			this.head = computeIndex(1);
			this.length--;
			final value = storage[old_head];
			storage[old_head] = null;
			return value;
		}
	}

	public function removeAt(idx:Int):Null<T> {
		if (length <= idx) {
			return null;
		} else {
			var storage_idx = computeIndex(idx);
			var value = storage[storage_idx];
			if (storage_idx >= head) {
				Vector.blit(storage, head, storage, head + 1, storage_idx - head);
				storage[head] = null;
				head++;
				length--;
			} else { // storage_idx < head
				Vector.blit(storage, storage_idx + 1, storage, storage_idx, length - idx - 1);
				storage[storage_idx + length - idx - 1] = null;
				length--;
			}
			return value;
		}
	}

	public function iterator():Iterator<T> {
		return new VecDequeIterator(this);
	}

	public function toString() {
		var b = new StringBuf();
		b.addChar("[".code);
		for (i in 0...length) {
			if (i > 0)
				b.addChar(",".code);
			b.add(storage[computeIndex(i)]);
		}
		b.addChar("]".code);
		return b.toString();
	}
}

private class VecDequeIterator<T> {
	var d:VecDeque<T>;
	var idx:Int;

	public inline function new(d:VecDeque<T>) {
		this.d = d;
		this.idx = 0;
	}

	public inline function hasNext():Bool {
		return idx < d.length;
	}

	public inline function next():T {
		return @:privateAccess d.storage[d.computeIndex(idx++)];
	}
}