package hxcoro.thread;

import haxe.coro.dispatchers.IDispatchObject;
import haxe.ds.Vector;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;
import sys.thread.Semaphore;
import sys.thread.Thread;
import sys.thread.Tls;
#if (!target.threaded)
#error "This class is not available on this target"
#end


/**
	The queue type used by `FixedThreadPool` for each worker and for the threads outside the pool.
**/
typedef DispatchQueue = WorkStealingQueue<IDispatchObject>;

private enum abstract PoolState(Int) to Int {
	/**
		The pool accepts work from all threads.
	**/
	final Active;
	/**
		A thread outside the pool is adding work, or `shutDown` is starting the shutdown.
	**/
	final Locked;
	/**
		The pool only accepts work from its own threads, and the workers exit once the queues are empty.
	**/
	final Draining;
}

/**
	Thread pool with a constant amount of threads.
	Threads in the pool will exist until the pool is explicitly shut down.
**/
class FixedThreadPool implements IThreadPool {
	/**
		@see `IThreadPool.threadsCount`
	**/
	public var threadsCount(get,null):Int;
	function get_threadsCount():Int return threadsCount;

	/**
		@see `IThreadPool.isShutDown`
	**/
	public var isShutDown(get,never):Bool;
	function get_isShutDown():Bool return state.load() == Draining;

	// Doubles as the lock of the threads outside the pool: they add work only while holding it
	// in `Active`, so once a worker sees `Draining`, all their work is in the queues.
	final state:AtomicState<PoolState>;
	final semaphore:Semaphore;
	final pool:Array<Worker>;
	final queueTls:Tls<DispatchQueue>;
	final sharedQueue:DispatchQueue;
	final ownerQueue:DispatchQueue;

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount:Int):Void {
		if(threadsCount < 1)
			throw new ThreadPoolException('FixedThreadPool needs threadsCount to be at least 1.');
		this.threadsCount = threadsCount;
		state = new AtomicState(Active);
		semaphore = new Semaphore(0);
		queueTls = new Tls();
		final queues = Vector.fromArrayCopy([for (_ in 0...threadsCount + 2) new WorkStealingQueue()]);
		// The constructing thread, which usually runs the scheduler loop, gets a queue of its
		// own. All other non-pool threads share a queue, which supports only one producer,
		// so that one is safe because they add only while holding the state lock.
		ownerQueue = queues[0];
		queueTls.value = ownerQueue;
		sharedQueue = queues[1];
		// Assigned before the workers are created, so that all fields are set when they get `this`.
		pool = [];
		for (i in 0...threadsCount) {
			pool.push(new Worker(this, queues, i + 2));
		}
		for (worker in pool) {
			worker.start();
		}
	}

	/**
		@see `IThreadPool.run`
	**/
	public function run(obj:IDispatchObject):Void {
		if(obj == null) {
			throw new ThreadPoolException('Task to run must not be null.');
		}
		final queue = queueTls.value;
		if (queue != null && queue != ownerQueue) {
			// A pool thread has its queue only while its worker loop runs, so the worker still
			// sees the object, also while the pool is draining.
			queue.add(obj);
		} else {
			if (!lock()) {
				throw new ThreadPoolException('Task is rejected. Thread pool is shut down.');
			}
			(queue ?? sharedQueue).add(obj);
			state.store(Active);
		}
		semaphore.release();
	}

	// Spins until the state goes from `Active` to `Locked`, or returns false once the pool is draining.
	function lock() {
		while (true) {
			switch (state.compareExchange(Active, Locked)) {
				case Active:
					return true;
				case Locked:
					BackOff.backOff();
				case Draining:
					return false;
			}
		}
	}

	/**
		@see `IThreadPool.shutdown`
	**/
	public function shutDown(block:Bool = false):Void {
		if (!lock()) {
			return;
		}

		final shutdownSemaphore = new Semaphore(0);
		// The workers get the semaphore before they can see `Draining`, which makes them exit.
		for (worker in pool) {
			worker.shutDown(shutdownSemaphore);
		}
		state.store(Draining);
		for (_ in pool) {
			semaphore.release();
		}
		if (block) {
			final ownQueue = queueTls.value;
			for (worker in pool) {
				// We could come here from a worker thread, in which case we can't wait for its
				// semaphore release.
				if (ownQueue != worker.queue) {
					shutdownSemaphore.acquire();
				}
			}
		}
	}

	/**
		Prints debugging information about this pool.
	**/
	public function dump() {
		Sys.println("FixedThreadPool");
		Sys.println('\tisShutDown: $isShutDown');
		var totalDispatches = 0i64;
		var totalLoops = 0i64;
		for (worker in pool) {
			totalDispatches += worker.numDispatched;
			totalLoops += worker.numLooped;
		}
		Sys.println('\ttotal worker loops: $totalLoops');
		Sys.println('\ttotal worker dispatches: $totalDispatches');
		Sys.print('\towner queue: ');
		ownerQueue.dump();
		Sys.print('\tshared queue: ');
		sharedQueue.dump();
		for (worker in pool) {
			final loopShare = worker.numLooped * 100 / totalLoops;
			final dispatchShare = worker.numDispatched * 100 / totalDispatches;
			Sys.print('\tworker ${@:privateAccess worker.ownQueueIndex}(${worker.state.toString()}), dispatch/loop: $dispatchShare%/$loopShare%, queue: ');
			worker.queue.dump();
		}
	}
}

private class ShutdownException extends ThreadPoolException {}

/**
	The state of a `FixedThreadPool` worker, as shown by `FixedThreadPool.dump`.
**/
@:using(FixedThreadPool.WorkerStateTools)
enum abstract WorkerState(Int) {
	final Created;
	final CheckingQueues;
	final Working;
	final Waiting;
	final Terminated;
}

private class WorkerStateTools {
	static public function toString(state:WorkerState) {
		return switch (state) {
			case Created: "Created";
			case CheckingQueues: "CheckingQueues";
			case Working: "Working";
			case Waiting: "Waiting";
			case Terminated: "Terminated";
		}
	}
}

/**
	This class represents a worker for a thread pool. Some implementation details are:

	- A worker isn't a thread; instead, it has a thread.
	- If the worker's thread terminates prematurely, a new thread is created.
	- When a thread is created, it installs the worker's queue as a TLS value. This
	  is what the pool's `run` function adds events to.
	- The worker loops over all queues, starting with its own, to look for events to steal
	  and execute.
	- Once all queues are empty, it waits on the condition variable.
	- If `shutDown` is called, the worker keeps executing events until the queues are empty.
**/
private class Worker {
	public var queue(get, never):DispatchQueue;
	public var state(default, null):WorkerState;
	public var numDispatched(default, null):Int;
	public var numLooped(default, null):Int;

	var shutdownSemaphore:Null<Semaphore>;
	final pool:FixedThreadPool;
	final semaphore:Semaphore;
	final queues:Vector<DispatchQueue>;
	final ownQueueIndex:Int;
	final queueTls:Tls<DispatchQueue>;

	public function new(pool:FixedThreadPool, queues:Vector<DispatchQueue>, ownQueueIndex:Int) {
		this.pool = pool;
		this.semaphore = @:privateAccess pool.semaphore;
		this.queues = queues;
		this.ownQueueIndex = ownQueueIndex;
		this.queueTls = @:privateAccess pool.queueTls;
		numDispatched = 0;
		numLooped = 0;
		state = Created;
	}

	function get_queue() {
		return queues[ownQueueIndex];
	}

	public function start() {
		var completed = false;
		// The exit callback is registered here, before the thread runs, so it is called after
		// every exit callback that code running on this thread registers with
		// `Thread.addCurrentCallbacks`, such as those of `ThreadAwareScheduler` and
		// `TrampolineDispatcher`. Only then does the thread count as gone for `shutDown`.
		Thread.create(null, () -> {
			threadEntry();
			completed = true;
		}, {
			onExit: () -> onThreadExit(completed)
		});
	}

	public function shutDown(shutdownSemaphore:Semaphore) {
		this.shutdownSemaphore = shutdownSemaphore;
	}

	function checkQueues() {
		var index = ownQueueIndex;
		var didSomething = false;
		while (true) {
			final queue = queues[index];
			final obj = queue.steal();
			if (obj != null) {
				state = Working;
				++numDispatched;
				obj.onDispatch();
				state = CheckingQueues;
				didSomething = true;
				// Loop with same index because there's a good chance there's more in
				// the current queue.
				continue;
			}
			if (index == queues.length - 1) {
				index = 0;
			} else {
				++index;
				if (index == ownQueueIndex) {
					return didSomething;
				}
			}
		}
	}

	function loop() {
		state = CheckingQueues;
		while(true) {
			++numLooped;

			// Read before checking the queues: once the pool is draining, the threads outside the
			// pool have added all their work, so a pass that finds nothing means that this worker is
			// done. The other workers run what their own dispatches add.
			final draining = @:privateAccess pool.state.load() == Draining;
			final didSomething = checkQueues();
			if (draining) {
				if (didSomething) {
					continue;
				}
				semaphore.release();
				break;
			}
			state = Waiting;
			semaphore.acquire();
			state = CheckingQueues;
		}
	}

	function threadEntry() {
		queueTls.value = queue;
		loop();
		// No worker sees work added from here on, such as from the exit callbacks of this thread,
		// so `run` treats the thread as outside the pool and rejects it.
		queueTls.value = null;
		state = Terminated;
	}

	function onThreadExit(completed:Bool) {
		queueTls.value = null;
		if (completed) {
			shutdownSemaphore?.release();
		} else {
			// An uncaught exception aborted the thread, and the thread's abort handler has
			// reported it. Replace the thread only now, once the old one has finished its
			// abort handling and exit callbacks, so that it cannot outlive the replacement.
			// If the pool is shutting down, the replacement drains the queues and releases
			// the shutdown semaphore in its own exit callback.
			start();
		}
	}
}