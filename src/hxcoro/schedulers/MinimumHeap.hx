package hxcoro.schedulers;

import haxe.ds.Vector;

/**
	A binary min-heap of `ScheduledEvent` instances, ordered by `runTime` and then by insertion
	order, so events with the same due time come out in the order they were inserted. It is not
	thread-safe.

	Each event has its own node. Schedulers extract and dispatch one event at a time, so if a
	dispatch throws, the events that were not dispatched yet are still in the heap.
**/
class MinimumHeap {
	var storage:Vector<Null<ScheduledEvent>>;
	var length:Int;
	var nextSequence:Int;

	public function new() {
		storage = new Vector(16);
		length = 0;
		nextSequence = 0;
	}

	/**
		Returns `true` if this heap contains no events.
	**/
	public function isEmpty() {
		return length == 0;
	}

	/**
		Returns the event that is due first without removing it, or `null` if this heap is empty.
	**/
	public inline function minimum() {
		return storage[0];
	}

	/**
		Inserts `event`.
	**/
	@:nullSafety(Off)
	public function insert(event:ScheduledEvent) {
		if (length == storage.length) {
			final newStorage = new Vector(storage.length << 1);
			Vector.blit(storage, 0, newStorage, 0, storage.length);
			storage = newStorage;
		}
		event.sequence = nextSequence++;
		var i = length++;
		while (i > 0) {
			final iParent = (i - 1) >> 1;
			final parentEvent = storage[iParent];
			if (!isBefore(event, parentEvent)) {
				break;
			}
			storage[i] = parentEvent;
			i = iParent;
		}
		storage[i] = event;
	}

	/**
		Removes and returns the event that is due first, or `null` if this heap is empty.
	**/
	@:nullSafety(Off)
	public function extract() {
		if (length == 0) {
			return null;
		}
		final root = storage[0];
		final last = storage[--length];
		storage[length] = null;
		if (length > 0) {
			// Sift `last` down from the root.
			var i = 0;
			while (true) {
				final l = (i << 1) + 1;
				if (l >= length) {
					break;
				}
				final r = l + 1;
				final child = r < length && isBefore(storage[r], storage[l]) ? r : l;
				if (!isBefore(storage[child], last)) {
					break;
				}
				storage[i] = storage[child];
				i = child;
			}
			storage[i] = last;
		}
		return root;
	}

	static inline function isBefore(a:ScheduledEvent, b:ScheduledEvent) {
		// The subtraction keeps the order correct when the sequence number wraps around, as long
		// as the events in the heap were inserted fewer than 2^31 insertions apart.
		return a.runTime < b.runTime || (a.runTime == b.runTime && a.sequence - b.sequence < 0);
	}
}
