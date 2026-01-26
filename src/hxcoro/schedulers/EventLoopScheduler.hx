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
	var childEvents:Array<IDispatchObject>;

	public function new(func, runTime) {
		this.func    = func;
		this.runTime = runTime;
	}

	public function addChildEvent(event:IDispatchObject) {
		childEvents ??= [];
		childEvents.push(event);
	}

	public inline function onDispatch() {
		final func = func;
		if (func != null) {
			this.func = null;
			func();
		}

		if (childEvents != null) {
			final childEvents = childEvents;
			this.childEvents = null;
			for (childEvent in childEvents) {
				childEvent.onDispatch();
			}
		}
	}

	public function iterateEvents(f:IDispatchObject->Void) {
		final childEvents = childEvents;
		this.childEvents = null;
		f(this);
		if (childEvents != null) {
			for (childEvent in childEvents) {
				f(childEvent);
			}
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

	function findFrom(i:Int, event:ScheduledEvent) {
		if (i >= length) {
			return false;
		}
		final currentEvent = storage[i];
		if (currentEvent == null || currentEvent.runTime > event.runTime) {
			return false;
		}
		if (currentEvent.runTime == event.runTime) {
			currentEvent.addChildEvent(event);
			return true;
		}
		return findFrom(left(i), event) || findFrom(right(i), event);
	}

	function revert(to:Int) {
		function loop(iCurrent:Int) {
			if (iCurrent != to) {
				final iParent = parent(iCurrent);
				loop(iParent);
				swap(iCurrent, iParent);
			}
		}
		loop(--length);
		storage[length] = null;
	}

	public function insert(event:ScheduledEvent) {
		ensureCapacity();
		storage[length++] = event;
		final runTime = event.runTime;
		var i = length - 1;
		while (i > 0) {
			final iParent = parent(i);
			final parentEvent = storage[iParent];
			if (parentEvent.runTime < runTime) {
				final iLeft = left(iParent);
				// go upward from our sibling
				if (findFrom(iLeft == i ? iLeft + 1 : iLeft, event)) {
					revert(i);
				}
				break;
			} else if (parentEvent.runTime == runTime) {
				parentEvent.addChildEvent(event);
				revert(i);
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
		}

		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}
}