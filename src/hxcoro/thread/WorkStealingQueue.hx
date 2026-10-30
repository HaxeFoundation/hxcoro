package hxcoro.thread;
import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicObject;
import hxcoro.ds.CircularVector;

/**
	Holds the slots of a `WorkStealingQueue`. `AtomicObject` needs a class instance, and the
	storage of `CircularVector` is a native array on some targets.
**/
private class Slots<T> {
	public final slots:CircularVector<T>;

	public function new(slots:CircularVector<T>) {
		this.slots = slots;
	}
}

/**
	A single-producer multi-consumer work-stealing queue.

	Only one thread may call `add`, but any number of threads may call `steal` concurrently,
	including the producer.

	The producer publishes everything it writes through atomic stores, which consumers load
	before reading the data:

	- A slot is written before `write` is advanced.
	- On a resize, the live slots are copied into the new storage before it is stored in
	  `storage`. A consumer that loaded `write` before the resize can still load the new
	  storage afterwards, and only the atomic `storage` makes the copied slots visible to it.
**/
class WorkStealingQueue<T> {
	final read:AtomicInt;
	final write:AtomicInt;
	final storage:AtomicObject<Slots<T>>;

	/**
		Creates a new work-stealing queue.
	**/
	public function new() {
		read = new AtomicInt(0);
		write = new AtomicInt(0);
		storage = new AtomicObject(new Slots(CircularVector.create(16)));
	}

	/**
		Returns the current slots.
	**/
	function loadSlots():CircularVector<T> {
		return loadHolder().slots;
	}

	/**
		On hxcpp, `AtomicObject.load` returns an untyped `hx::Object`, so a field access directly
		on its result fails to compile. The declared return type makes hxcpp convert it. This is
		not inline, so the conversion can't be optimized away.
	**/
	function loadHolder():Slots<T> {
		return storage.load();
	}

	function resize(slots:CircularVector<T>, from:Int, to:Int) {
		final newSlots = CircularVector.create(slots.length << 1);
		for (i in from...to) {
			newSlots[i] = slots[i];
		}
		return newSlots;
	}

	/**
		Adds `value` to this queue.

		This function must only be called by the queue's single producer thread. It might also
		cause allocations in case the underlying storage has to be expanded.
	**/
	public function add(value:T) {
		final w = write.load();
		final r = read.load();
		var slots = loadSlots();
		if (w - r >= slots.length) {
			slots = resize(slots, r, w);
			storage.store(new Slots(slots));
		}
		slots[w] = value;
		write.add(1);
	}

	/**
		Tries to remove an element from this queue. If no element is available,
		`null` is returned.

		This function is thread-safe. Note that a `null` return value does not
		necessarily mean that the queue is empty: if several threads steal at the
		same time, all but one of them can get `null`. With a single consumer, it
		does mean that the queue is empty.
	**/
	public function steal() {
		final r = read.load();
		final w = write.load();
		final size = w - r;
		if (size <= 0) {
			return null;
		}
		final v = loadSlots()[r];
		if (read.compareExchange(r, r + 1) == r) {
			return v;
		} else {
			return null;
		}
	}

	/**
		Prints debugging information about this queue.
	**/
	public function dump() {
		final r = read.load();
		final w = write.load();
		final slots = loadSlots();
		Sys.print('(r $r, w $w, l ${slots.length}): ');
		for (i in r...w) {
			if (i != r) {
				Sys.print(" ");
			}
			Sys.print(slots.get(i));
		}
		Sys.println("");
	}
}
