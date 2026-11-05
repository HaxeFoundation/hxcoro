package hxcoro.schedulers;

import sys.thread.ThreadCallback;
import haxe.Int64;
import haxe.Timer;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;
import hxcoro.schedulers.ILoop;
import hxcoro.thread.WorkStealingQueue;
import sys.thread.Deque;
import sys.thread.Thread;
import sys.thread.Tls;

/**
	The queue that a thread schedules its events into. It is shared between two threads: the
	thread that owns it is the only producer, and the loop thread is the only consumer. Being
	a TLS value only rules out competing producers, so the queue still has to publish its
	events to the loop thread, which `WorkStealingQueue` does with atomic stores and loads.
**/
private typedef TlsQueue = WorkStealingQueue<ScheduledEvent>;

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
	WakeUp;
}

/**
	A scheduler for multi-threaded setups such as `hxcoro.run.Setup.createThreadPool`.
**/
class ThreadAwareScheduler implements IScheduler implements ILoop {
	final heap:MinimumHeap;
	final queueTls:Tls<TlsQueue>;
	final queueDeque:Deque<ThreadQueueEvent>;
	final wakeUpFlag:WakeUpFlag;
	var firstQueue:Null<ThreadQueue>;

	public function new() {
		heap = new MinimumHeap();
		queueTls = new Tls();
		queueDeque = new Deque();
		wakeUpFlag = new WakeUpFlag();
	}

	function getTlsQueue():TlsQueue {
		var threadQueue = queueTls.value;
		if (threadQueue != null) {
			return threadQueue;
		}

		final newQueue = new WorkStealingQueue();
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
		wakeUpFlag.set();
		return event;
    }

	public function now() {
		return Timer.milliseconds();
	}

	/**
		Processes the coordination deque and returns whether it contained a `WakeUp`.
	**/
	function consumeQueueDeque() {
		var wokenUp = false;
		while (true) {
			switch (queueDeque.pop(false)) {
				case null:
					return wokenUp;
				case WakeUp:
					wokenUp = true;
				case Add(queue):
					// We don't care about the order, so treat it as a stack
					final first = firstQueue;
					firstQueue = queue;
					firstQueue.next = first;
					if (first != null) {
						first.prev = firstQueue;
					}
				case Remove(queue):
					// The thread added its last events before it queued the removal, so move
					// them into the heap before forgetting the queue.
					drainQueue(queue.queue);
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

	function drainQueue(queue:TlsQueue) {
		while (true) {
			// This thread is the only consumer, so `steal` only returns null if the queue is empty.
			final event = queue.steal();
			if (event == null) {
				return;
			}
			heap.insert(event);
		}
	}

	function loopNoWait() {
		final currentTime = now();

		// First we consume the coordination deque so we know all queues.
		final wokenUp = consumeQueueDeque();

		// Move the events from the threads' queues into the heap, so that all events are
		// dispatched from one place, in order of due time.
		var current = firstQueue;
		while (current != null) {
			drainQueue(current.queue);
			current = current.next;
		}

		// Dispatch the due events one at a time, so that the ones after an event whose dispatch
		// throws stay in the heap. Only this thread touches the heap, and events scheduled while
		// dispatching go to a thread queue, so this loop ends.
		var didSomething = wokenUp;
		while (true) {
			final minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				return didSomething;
			}
			heap.extract();
			didSomething = true;
			minimum.dispatch();
		}
	}

	/**
		Collects the events from the queues of all threads and dispatches the due ones. In
		`Once` mode, if no event is due, this blocks until an event has been dispatched or
		`wakeUp` is called.

		This must not be called from multiple threads at the same time.
	**/
	public function loop(runMode:RunMode) {
		while (true) {
			// Clear the flag before collecting the threads' queues. The events that set it so
			// far are collected below, and any event scheduled from now on sets it again, so
			// the wait below can't miss it.
			wakeUpFlag.clear();
			if (loopNoWait() || runMode == NoWait) {
				return;
			}
			// Wait until the earliest event is due, or until something happens if there is none.
			wakeUpFlag.waitUntil(heap.minimum()?.runTime, now());
		}
	}

	/**
		Makes the current or next `loop(Once)` call return. This may be called from any thread.
	**/
	public function wakeUp() {
		// This goes through the coordination deque instead of `schedule`, so that it doesn't give
		// the calling thread an event queue of its own.
		queueDeque.add(WakeUp);
		wakeUpFlag.set();
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
			Sys.println('\tqueue: (r ${current.queue.read.load()}, w ${current.queue.write.load()}, l: ${current.queue.storage.load().slots.length})');
			totalWrites += current.queue.write.load();
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