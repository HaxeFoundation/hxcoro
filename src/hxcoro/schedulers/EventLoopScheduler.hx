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

	public function close() {
		func = null;
	}
}

private class MinimumHeap {
	final storage : Array<ScheduledEvent>;

	public function new() {
		storage = [];
	}

	public function left(i:Int) {
		return (i << 1) + 1;
	}

	public function right(i:Int) {
		return (i << 1) + 2;
	}

	public function parent(i:Int) {
		return (i - 1) >> 1;
	}

	public function minimum() {
		if (storage.length == 0) {
			return null;
		}

		return storage[0];
	}

	function revert(to:Int) {
		function loop(iCurrent:Int) {
			if (iCurrent != to) {
				final iParent = parent(iCurrent);
				loop(iParent);
				swap(iCurrent, iParent);
			}
		}
		loop(storage.length - 1);
		storage.pop();
	}

	public function insert(event:ScheduledEvent) {
		final minEvent = minimum();
		if (minEvent != null && minEvent.runTime == event.runTime) {
			minEvent.addChildEvent(event);
			return;
		}
		storage.push(event);
		final runTime = event.runTime;
		var i = storage.length - 1;
		while (i > 0) {
			final iParent = parent(i);
			final parentEvent = storage[iParent];
			if (parentEvent.runTime < runTime) {
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
			if (l < storage.length && storage[l].runTime < storage[smallest].runTime) {
				smallest = l;
			}
			if (r < storage.length && storage[r].runTime < storage[smallest].runTime) {
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

	public function new() {
		super();

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

	public function scheduleObject(obj:IScheduleObject) {
		final currentTime = now();
		futureMutex.acquire();
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
			toRun.onSchedule();
		}

		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}
}