package hxcoro.thread;
import hxcoro.concurrent.AtomicInt;
import hxcoro.ds.CircularVector;

/**
	A single-producer multi-consumer work-stealing queue.
**/
class WorkStealingQueue<T> {
	final read:AtomicInt;
	final write:AtomicInt;
	var storage:CircularVector<T>;

	/**
		Creates a new work-stealing queue.
	**/
	public function new() {
		read = new AtomicInt(0);
		write = new AtomicInt(0);
		storage = CircularVector.create(16);
	}

	function resize(from:Int, to:Int) {
		final newStorage = CircularVector.create(storage.length << 1);
		for (i in from...to) {
			newStorage[i] = storage[i];
		}
		return newStorage;
	}

	/**
		Adds `value` to this queue.

		This function is not thread-safe. It might also cause allocations in
		case the underlying storage has to be expanded.
	**/
	public function add(value:T) {
		final w = write.load();
		final r = read.load();
		final sizeNeeded = w - r;
		if (sizeNeeded >= storage.length) {
			final storage = resize(r, w);
			storage[w] = value;
			this.storage = storage;
			write.add(1);
		} else {
			storage[w] = value;
			write.add(1);
		}
	}

	/**
		Tries to remove an element from this queue. If no element is available,
		`null` is returned.

		This function is thread-safe. Note that a `null` return value does not
		necessarily mean that the queue is empty, because the operation could
		fail for other reasons.
	**/
	public function steal() {
		final r = read.load();
		final w = write.load();
		final size = w - r;
		if (size <= 0) {
			return null;
		}
		final storage = storage;
		final v = storage[r];
		if (read.compareExchange(r, r + 1) == r) {
			return v;
		} else {
			return null;
		}
	}

	/**
		Resets the queues internal indices and sets all storage values
		to `null`. This function does not verify the absence of elements
		in the queue, so it should only be called when it is certain that
		no accessible elements exist.

		Does not resize the internal storage.
	**/
	public function reset() {
		final w = write.exchange(0);
		if (w == 0) {
			return;
		}
		read.store(0);
		for (i in 0...w) {
			storage[i] = null;
		}
	}

	public function dump() {
		final r = read.load();
		final w = write.load();
		Sys.print('(r $r, w $w, l ${storage.length}): ');
		for (i in r...w) {
			if (i != r) {
				Sys.print(" ");
			}
			Sys.print(storage.get(i));
		}
		Sys.println("");
	}
}