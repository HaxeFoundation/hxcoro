package hxcoro.schedulers;

import haxe.exceptions.NotImplementedException;
import haxe.Timer;
import haxe.Int64;
import haxe.coro.Mutex;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;

private typedef Lambda = ()->Void;
private typedef CloseClosure = (handle:ISchedulerHandle)->Void;

private class ScheduledEvent implements ISchedulerHandle {
	final closure : CloseClosure;
	final func : Lambda;
	var closed : Bool;
	public final runTime : Int64;

	public function new(closure, func, runTime) {
		this.closure = closure;
		this.func    = func;
		this.runTime = runTime;

		closed   = false;
	}

	public inline function run() {
		func();

		closed = true;
	}

	public function close() {
		if (closed) {
			return;
		}

		closure(this);

		closed = true;
	}
}

private class NoOpHandle implements ISchedulerHandle {
	public function new() {}
	public function close() {}
}

private class DoubleBuffer<T> {
	final a : Array<T>;
	final b : Array<T>;

	var current : Array<T>;

	public function new() {
		a       = [];
		b       = [];
		current = a;
	}

	public function flip() {
		final returning = current;

		current = if (current == a) b else a;
		current.resize(0);

		return returning;
	}

	public function push(l : T) {
		current.push(l);
	}

	public function empty() {
		return current.length == 0;
	}
}

class FunctionScheduleObject implements IScheduleObject {
	var func:() -> Void;

	public function new(func:() -> Void) {
		this.func = func;
	}

	public function onSchedule() {
		func();
	}
}

private class MinimumHeap {
	final storage : Array<ScheduledEvent>;

	public function new() {
		storage = [];
	}

	public function left(i:Int) {
		return 2 * i + 1;
	}

	public function right(i:Int) {
		return 2 * i + 2;
	}

	public function parent(i:Int) {
		return Math.floor((i - 1) / 2);
	}

	public function minimum() {
		if (storage.length == 0) {
			return null;
		}

		return storage[0];
	}

	public function insert(event:ScheduledEvent) {
		storage.push(event);

		var i = storage.length - 1;
		while (i > 0 && storage[parent(i)].runTime > storage[i].runTime) {
			final p = parent(i);

			swap(i, p);

			i = p;
		}
	}

	public function extract() {
		if (storage.length == 0) {
			return null;
		}

		if (storage.length == 1) {
			return storage.pop();
		}

		final root = minimum();
		storage[0] = storage[storage.length - 1];
		storage.pop();

		heapify(0);

		return root;
	}

	function swap(fst:Int, snd:Int) {
		final temp = storage[fst];
		storage[fst] = storage[snd];
		storage[snd] = temp;
	}

	function heapify(index:Int) {
		final l = left(index);
		final r = right(index);

		var smallest = index;
		if (l < storage.length && storage[l].runTime < storage[smallest].runTime) {
			smallest = l;
		}
		if (r < storage.length && storage[r].runTime < storage[smallest].runTime) {
			smallest = r;
		}

		if (smallest != index) {
			swap(index, smallest);
			heapify(smallest);
		}
	}
}

class EventLoopScheduler extends Scheduler {
	final noOpHandle : NoOpHandle;
	final zeroEvents : DoubleBuffer<IScheduleObject>;
	final zeroMutex : Mutex;
	final futureMutex : Mutex;
	final heap : MinimumHeap;
	final closeClosure : CloseClosure;

	public function new() {
		super();

		noOpHandle   = new NoOpHandle();
		zeroEvents   = new DoubleBuffer();
		zeroMutex    = new Mutex();
		futureMutex  = new Mutex();
		heap         = new MinimumHeap();
		closeClosure = close;
	}

    public function schedule(ms:Int64, func:()->Void):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		} else if (ms == 0) {
			zeroMutex.acquire();
			zeroEvents.push(new FunctionScheduleObject(func));
			zeroMutex.release();
			return noOpHandle;
		}

		final event = new ScheduledEvent(closeClosure, func, now() + ms);

		futureMutex.acquire();

		heap.insert(event);

		futureMutex.release();

		return event;
    }

	public function scheduleObject(obj:IScheduleObject) {
		zeroMutex.acquire();
		zeroEvents.push(obj);
		zeroMutex.release();
	}

	public function now() {
		return Timer.milliseconds();
	}

	function runZeroEvents() {
		zeroMutex.acquire();
		final events = zeroEvents.flip();
		// no need to hold onto the mutex because it's a double buffer and run itself is single-threaded
		zeroMutex.release();
		for (obj in events) {
			obj.onSchedule();
		}
	}

	public function run() {
		runZeroEvents();

		final currentTime = now();

		futureMutex.acquire();

		while (true) {
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				break;
			}

			heap.extract().run();
		}
		
		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}

	function close(handle : ISchedulerHandle) {
		throw new NotImplementedException();
		// var current = first;
		// while (true) {
		// 	if (null == current) {
		// 		return;
		// 	}

		// 	if (current == handle) {
		// 		if (first == current) {
		// 			first = current.next;
		// 		} else {
		// 			final a = current.previous;
		// 			final b = current.next;

		// 			a.next = b;
		// 			b?.previous = a;
		// 		}

		// 		return;
		// 	} else {
		// 		current = current.next;
		// 	}
		// }
	}
}