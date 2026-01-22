package hxcoro.thread;
import haxe.ds.Vector;
import hxcoro.concurrent.AtomicInt;

private abstract Storage<T>(Vector<T>) {
	public var length(get, never):Int;

	public inline function new(vector:Vector<T>) {
		this = vector;
	}

	public inline function get_length() {
		return this.length;
	}

	@:arrayAccess public inline function get(i:Int) {
		// `& (x - 1)` is the same as `% x` when x is a power of two
		return this[i & (this.length - 1)];
	}

	@:arrayAccess public inline function set(i:Int, v:T) {
		return this[i & (this.length - 1)] = v;
	}
}

/**
	A single-producer multi-consumer work-stealing queue.
**/
class WorkStealingQueue<T> {
	final read:AtomicInt;
	final write:AtomicInt;
	var storage:Storage<T>;

	/**
		Creates a new work-stealing queue.
	**/
	public function new() {
		read = new AtomicInt(0);
		write = new AtomicInt(0);
		storage = new Storage(new Vector(16));
	}

	function resize(from:Int, to:Int) {
		final newStorage = new Storage(new Vector(storage.length << 1));
		for (i in from...to) {
			newStorage[i] = storage[i];
		}
		storage = newStorage;
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
		if (sizeNeeded >= storage.length - 1) {
			resize(r, w);
		}
		storage[w] = value;
		write.add(1);
	}

	/**
		Tries to remove an element from this queue. If no element is available,
		`null` is returned.

		This function is thread-safe. Note that a `null` return value does not
		necessarily mean that the queue is empty, because the operation could
		fail for other reasons.
	**/
	public function steal() {
		while (true) {
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
				// loop to try again
			}
		}
	}
}