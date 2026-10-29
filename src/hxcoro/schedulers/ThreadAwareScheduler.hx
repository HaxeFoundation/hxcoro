package hxcoro.schedulers;

import sys.thread.ThreadCallback;
import haxe.Int64;
import haxe.Timer;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;
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

private class ThreadQueue {
	public final queue:TlsQueue;

	public var onExitHandle:Null<IThreadCallbackHandle>;
	public var prev:Null<ThreadQueue>;
	public var next:Null<ThreadQueue>;

	public function new(queue:TlsQueue) {
		this.queue = queue;
	}
}

private enum ThreadQueueEvent {
	Add(queue:ThreadQueue);
	Remove(queue:ThreadQueue);
}

/**
	A scheduler for multi-threaded setups such as `hxcoro.run.Setup.createThreadPool`.
**/
class ThreadAwareScheduler implements IScheduler implements ILoop {
	final heap:MinimumHeap;
	final queueTls:Tls<TlsQueue>;
	final queueDeque:Deque<ThreadQueueEvent>;
	final rootEvent:ScheduledEvent;
	final semaphore:Semaphore;
	var firstQueue:Null<ThreadQueue>;

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
		final threadQueue = new ThreadQueue(newQueue);
		final handle = Thread.addCurrentCallbacks({onExit: function() {
			queueDeque.add(Remove(threadQueue));
			queueTls.value = null;
		}});
		threadQueue.onExitHandle = handle;
		queueTls.value = newQueue;
		queueDeque.add(Add(threadQueue));
		return newQueue;
	}

	/**
		Adds the event to a queue owned by the calling thread. This may be called from
		any thread.
	**/
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
				final queue = current.queue;
				event = queue.pop();
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
			try {
				event.dispatch(heap.insert);
			} catch (e:haxe.Exception) {
				// Put the rest of the due events back into the heap so the next loop dispatches them.
				var rest = event.next;
				rootEvent.next = null;
				while (rest != null) {
					final next = rest.next;
					rest.next = null;
					heap.insert(rest);
					rest = next;
				}
				throw e;
			}
		}
	}

	/**
		Collects the events from the queues of all threads and dispatches the due ones. In
		`Once` mode, if no event is due, this blocks until the next event is due, a new event
		is scheduled, or `wakeUp` is called.

		This must not be called from multiple threads at the same time.
	**/
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

	/**
		Prints debugging information about this scheduler.
	**/
	public function dump() {
		Sys.println("ThreadAwareScheduler");
		Sys.println('\theap minimum: ${heap.minimum()}');
		var current = firstQueue;
		var totalWrites = 0;
		@:privateAccess while (current != null) {
			Sys.println('\tqueue: (r ${current.queue.read}, w ${current.queue.write}, l: ${current.queue.storage.length})');
			totalWrites += current.queue.write;
			current = current.next;
		}
		Sys.println('\ttotal writes: $totalWrites');
	}

	/**
		Returns a string representation of this scheduler.
	**/
	public function toString() {
		return '[ThreadAwareScheduler]';
	}
}