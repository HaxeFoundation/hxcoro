package hxcoro.schedulers;

import haxe.ds.Vector;
import haxe.Timer;
import haxe.Int64;
import haxe.coro.Mutex;
import hxcoro.dispatchers.IDispatcher;
import hxcoro.dispatchers.SelfDispatcher;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;

private typedef Lambda = ()->Void;

private class ScheduledEvent implements ISchedulerHandle implements IScheduleObject {
	var func : Null<Lambda>;
	public final runTime : Int64;
	var childEvents:Array<IScheduleObject>;

	public function new(func, runTime) {
		this.func    = func;
		this.runTime = runTime;
	}

	public function addChildEvent(event:IScheduleObject) {
		childEvents ??= [];
		childEvents.push(event);
	}

	public inline function onSchedule() {
		if (func != null) {
			final func = func;
			this.func = null;
			func();
		}

		if (childEvents != null) {
			final childEvents = childEvents;
			this.childEvents = null;
			for (childEvent in childEvents) {
				childEvent.onSchedule();
			}
		}
	}

	public function iterateEvents(f:IScheduleObject->Void) {
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
		final minEvent = minimum();
		if (minEvent != null && minEvent.runTime == event.runTime) {
			minEvent.addChildEvent(event);
			return;
		}
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

class EventLoopScheduler extends Scheduler {
	final futureMutex : Mutex;
	final heap : MinimumHeap;
	final dispatcher : IDispatcher;

	public function new(?dispatcher:IDispatcher) {
		super();

		futureMutex  = new Mutex();
		heap         = new MinimumHeap();
		#if (target.threaded && !eval && !python)
		this.dispatcher = dispatcher ?? new hxcoro.dispatchers.ThreadPoolDispatcher(new hxcoro.thread.FixedThreadPool(1));
		#else
		this.dispatcher = dispatcher ?? new SelfDispatcher();
		#end
	}

	public function hasEvents() {
		return !heap.isEmpty();
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

	public function scheduleObject(obj:IScheduleObject) {
		futureMutex.acquire();
		final currentTime = now();
		final first = heap.minimum();
		if (first == null || first.runTime > currentTime) {
			// add normal event at front
			final event = new ScheduledEvent(() -> obj.onSchedule(), currentTime);
			heap.insert(event);
		} else {
			// attach to first event
			first.addChildEvent(obj);
		}
		futureMutex.release();
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

			toRun.iterateEvents(dispatch);
		}

		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}

	function dispatch(obj:IScheduleObject) {
		dispatcher.dispatch(obj);
	}
}