package hxcoro.schedulers;

import haxe.Timer;
import haxe.Int64;
import haxe.ds.Vector;
import haxe.coro.Mutex;
import haxe.exceptions.ArgumentException;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.coro.dispatchers.IDispatchObject;

private typedef Lambda = ()->Void;

private class ScheduledEvent implements ISchedulerHandle implements IDispatchObject {
	var func : Null<Lambda>;
	public final runTime : Int64;

	public function new(func, runTime) {
		this.func    = func;
		this.runTime = runTime;
	}

	public inline function onDispatch() {
		final func = func;
		if (func != null) {
			this.func = null;
			func();
		}
	}

	public function close() {
		func = null;
	}
}

private class MinimumHeap {
	var storage : Vector<ScheduledEvent>;
	var length : Int;

	public function new() {
		storage = new Vector(16);
		length = 0;
	}

	public function isEmpty() {
		return length == 0;
	}

	public inline function left(i:Int) {
		return (i << 1) + 1;
	}

	public inline function right(i:Int) {
		return (i << 1) + 2;
	}

	public inline function parent(i:Int) {
		return (i - 1) >> 1;
	}

	public inline function minimum() {
		return storage[0];
	}

	function ensureCapacity() {
		if (length == storage.length) {
			final newStorage = new Vector(storage.length << 1);
			Vector.blit(storage, 0, newStorage, 0, storage.length);
			storage = newStorage;
		}
	}

	public function insert(event:ScheduledEvent) {
		ensureCapacity();
		storage[length++] = event;
		final runTime = event.runTime;
		var i = length - 1;
		while (i > 0) {
			final iParent = parent(i);
			final parentEvent = storage[iParent];
			if (parentEvent.runTime <= runTime) {
				break;
			}
			swap(i, iParent);
			i = iParent;
		}
	}

	public function extract() {
		return switch (length) {
			case 0:
				null;
			case 1:
				final ret = storage[--length];
				storage[0] = null;
				return ret;
			case _:
				final root = minimum();
				storage[0] = storage[--length];
				storage[length] = null;
				heapify(0);
				root;
		}
	}

	inline function swap(fst:Int, snd:Int) {
		final temp = storage[fst];
		storage[fst] = storage[snd];
		storage[snd] = temp;
	}

	function heapify(index:Int) {
		while (true) {
			final l = left(index);
			final r = right(index);

			var smallest = index;
			if (l < length && storage[l].runTime < storage[smallest].runTime) {
				smallest = l;
			}
			if (r < length && storage[r].runTime < storage[smallest].runTime) {
				smallest = r;
			}

			if (smallest != index) {
				swap(index, smallest);
				index = smallest;
			} else {
				break;
			}
		}
	}
}

class EventLoopScheduler implements IScheduler {
	final futureMutex : Mutex;
	final heap : MinimumHeap;

	public function new() {
		futureMutex  = new Mutex();
		heap         = new MinimumHeap();
	}

    public function schedule(ms:Int64, func:()->Void):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		final event = new ScheduledEvent(func, now() + ms);

		futureMutex.acquire();

		heap.insert(event);

		futureMutex.release();

		return event;
    }

	public function now() {
		return Timer.milliseconds();
	}

	public function run() {
		final currentTime = now();
		while (true) {
			futureMutex.acquire();
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				break;
			}

			final toRun = heap.extract();
			futureMutex.release();

			toRun.onDispatch();

			if (now() - currentTime > 10000) {
				// TODO: shouldn't be here
				break;
			}
		}

		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}
}