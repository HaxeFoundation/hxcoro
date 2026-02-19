package hxcoro.schedulers;

import haxe.Int64;
import haxe.Timer;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;
import hxcoro.concurrent.AtomicInt;
import hxcoro.ds.CircularVector;
import hxcoro.schedulers.ILoop;
import sys.thread.Deque;
import sys.thread.Semaphore;
import sys.thread.Thread;
import sys.thread.Tls;

private class CircularQueueData {
	public var read:Int;
	public var write:Int;
	public var storage:CircularVector<ScheduledEvent>;

	public function new() {
		read = write = 0;
		storage = CircularVector.create(1);
	}
}

private class CircularQueue {
	public var prev:Null<CircularQueue>;
	public var next:Null<CircularQueue>;

	var read:Int;
	var write:Int;
	var storage:CircularVector<ScheduledEvent>;

	public function new(size:Int) {
		storage = CircularVector.create(size);
		read = 0;
		write = 0;
	}

	function resize(from:Int, to:Int) {
		final newStorage = CircularVector.create(storage.length << 1);
		for (i in from...to) {
			newStorage[i] = storage[i];
		}
		storage = newStorage;
	}

	public function add(value:ScheduledEvent) {
		final w = write;
		final r = read;
		final sizeNeeded = w - r;
		if (sizeNeeded >= storage.length) {
			resize(r, w);
		}
		storage[w] = value;
		++write;
	}

	public function pop() {
		final r = read;
		final w = write;
		if (w - r <= 0) {
			return null;
		}
		return storage[read++];
	}

	public function toString() {
		return 'CircularQueue(r $read, w $write, l ${storage.length})';
	}
}

private typedef TlsQueue = CircularQueue;

private enum TlsQueueEvent {
	Add(queue:TlsQueue);
	Remove(queue:TlsQueue);
}

class ThreadAwareScheduler implements IScheduler implements ILoop {
	final heap:MinimumHeap;
	final queueTls:Tls<TlsQueue>;
	final queueDeque:Deque<TlsQueueEvent>;
	final rootEvent:ScheduledEvent;
	final semaphore:Semaphore;
	var firstQueue:Null<TlsQueue>;

	public function new() {
		heap = new MinimumHeap();
		queueTls = new Tls();
		queueDeque = new Deque();
		rootEvent = new ScheduledEvent(null, 0);
		semaphore = new Semaphore(0);
	}

	function getTlsQueue():TlsQueue {
		var threadQueue = queueTls.value;
		if (threadQueue != null) {
			return threadQueue;
		}

		final newQueue = new CircularQueue(4);
		final currentThread = Thread.current();
		currentThread.onExit(function() {
			queueDeque.add(Remove(newQueue));
			queueTls.value = null;
		});
		queueTls.value = newQueue;
		queueDeque.add(Add(newQueue));
		return newQueue;
	}

    public function schedule(ms:Int64, cont:IContinuation<Any>):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		final event = new ScheduledEvent(cont, now() + ms);
		getTlsQueue().add(event);
		semaphore.release();
		return event;
    }

	public function now() {
		return Timer.milliseconds();
	}

	function consumeQueueDeque() {
		while (true) {
			switch (queueDeque.pop(false)) {
				case null:
					return;
				case Add(queue):
					// We don't care about the order, so treat it as a stack
					final first = firstQueue;
					firstQueue = queue;
					firstQueue.next = first;
					if (first != null) {
						first.prev = firstQueue;
					}
				case Remove(queue):
					if (queue.next != null) {
						queue.next.prev = queue.prev;
					}
					if (queue.prev != null) {
						queue.prev.next = queue.next;
					}
					if (queue == firstQueue) {
						firstQueue = queue.next;
					}
			}
		}
	}

	function loopNoWait() {
		final currentTime = now();

		// First we consume the coordination deque so we know all queues.
		consumeQueueDeque();

		var currentEvent = rootEvent;

		// Next we dispatch all expired and current events in the heap.
		while (true) {
			var minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				break;
			}

			heap.extract();
			currentEvent.next = minimum;
			currentEvent = minimum;
		}

		// Now we loop over all queues from the threads.
		var current = firstQueue;
		while (current != null) {
			// Copy current slice data to our outQueue and iterate it.
			var event:Null<ScheduledEvent>;
			while (true) {
				event = current.pop();
				if (event == null) {
					break;
				}
				if (event.runTime > currentTime) {
					// Future events are added to the heap.
					heap.insert(event);
				} else {
					// Other events are dispatched immediately.
					currentEvent.next = event;
					currentEvent = event;
				}
			}
			current = current.next;
		}
		currentEvent.next = null;
		var event:Null<ScheduledEvent> = rootEvent;
		var didSomething = false;
		while (true) {
			event = event.next;
			if (event == null) {
				rootEvent.next = null;
				return didSomething;
			}
			didSomething = true;
			event.dispatch();
		}
	}

	public function loop(runMode:RunMode) {
		var wasWokenUp = false;
		while(true) {
			if (loopNoWait() || wasWokenUp || runMode == NoWait) {
				// If we did something we're fine.
				return;
			}
			final minimum = heap.minimum();
			if (minimum != null) {
				// If there's a scheduled event, its due time is our max timeout time.
				final timeout:Float = (Int64.toInt(minimum.runTime - now())) / 1000;
				semaphore.tryAcquire(timeout);
			} else {
				// Otherwise we wait until something happens.
				semaphore.acquire();
			}
			wasWokenUp = true;
		}
	}

	public function wakeUp() {
		semaphore.release();
	}

	public function dump() {
		Sys.println("ThreadAwareScheduler");
		Sys.println('\theap minimum: ${heap.minimum()}');
		var current = firstQueue;
		var totalWrites = 0;
		@:privateAccess while (current != null) {
			Sys.println('\tqueue: (r ${current.read}, w ${current.write}, l: ${current.storage.length})');
			totalWrites += current.write;
			current = current.next;
		}
		Sys.println('\ttotal writes: $totalWrites');
	}

	public function toString() {
		return '[ThreadAwareScheduler]';
	}
}