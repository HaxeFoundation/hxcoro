package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import haxe.coro.dispatchers.IDispatchObject;
import haxe.ds.Vector;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;
import sys.thread.Condition;
import sys.thread.Semaphore;
import sys.thread.Thread;
import sys.thread.Tls;

typedef DispatchQueue = WorkStealingQueue<IDispatchObject>;

private class WorkerActivity {
	public var activeWorkers:Int;
	public var availableWorkers:Int;

	/**
		Conversely, this is set when the mutex could be acquired and deals with a special case
		where we signal the condition variable before the worker thread waits on it. In particular,
		this can happen with a thread pool of size 1.
	**/
	public var hadEvent:Bool;

	public function new(activeWorkers:Int) {
		this.activeWorkers = activeWorkers;
		this.availableWorkers = activeWorkers;
		hadEvent = false;
	}
}

private enum abstract ShutdownState(Int) to Int {
	final Active;
	final ShuttingDown;
	final ShutDown;
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
	function get_isShutDown():Bool return shutdownState.load() != Active;

	final shutdownState:AtomicState<ShutdownState>;
	final semaphore:Semaphore;
	final pool:Array<Worker>;
	final queueTls:Tls<DispatchQueue>;

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount:Int):Void {
		if(threadsCount < 1)
			throw new ThreadPoolException('FixedThreadPool needs threadsCount to be at least 1.');
		this.threadsCount = threadsCount;
		shutdownState = new AtomicState(Active);
		semaphore = new Semaphore(0);
		queueTls = new Tls();
		final queues = Vector.fromArrayCopy([for (_ in 0...threadsCount + 1) new WorkStealingQueue()]);
		queueTls.value = queues[0];
		pool = [for(i in 0...threadsCount) new Worker(semaphore, queueTls, queues, i + 1)];
		for (worker in pool) {
			worker.start();
		}
	}

	/**
		@see `IThreadPool.run`
	**/
	public function run(obj:IDispatchObject):Void {
		if(isShutDown) {
			throw new ThreadPoolException('Task is rejected. Thread pool is shut down.');
		}
		if(obj == null) {
			throw new ThreadPoolException('Task to run must not be null.');
		}
		@:nullSafety(Off) queueTls.value.add(obj);
		semaphore.release();
	}

	/**
		@see `IThreadPool.shutdown`
	**/
	public function shutDown(block:Bool = false):Void {
		if (shutdownState.compareExchange(Active, ShuttingDown) != Active) {
			return;
		}

		final shutdownSemaphore = new Semaphore(0);

		for (worker in pool) {
			worker.shutDown(shutdownSemaphore);
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
		shutdownState.store(ShutDown);
	}

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
		Sys.print('\tqueue 0: ');
		queueTls.value?.dump();
		for (worker in pool) {
			final loopShare = worker.numLooped * 100 / totalLoops;
			final dispatchShare = worker.numDispatched * 100 / totalDispatches;
			Sys.print('\tworker ${@:privateAccess worker.ownQueueIndex}(${worker.state.toString()}), dispatch/loop: $dispatchShare%/$loopShare%, queue: ');
			worker.queue.dump();
		}
	}
}

private class ShutdownException extends ThreadPoolException {}

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
	final semaphore:Semaphore;
	final queues:Vector<DispatchQueue>;
	final ownQueueIndex:Int;
	final queueTls:Tls<DispatchQueue>;

	public function new(semaphore:Semaphore, queueTls:Tls<DispatchQueue>, queues:Vector<DispatchQueue>, ownQueueIndex:Int) {
		this.semaphore = semaphore;
		this.queues = queues;
		this.ownQueueIndex = ownQueueIndex;
		this.queueTls = queueTls;
		numDispatched = 0;
		numLooped = 0;
		state = Created;
	}

	function get_queue() {
		return queues[ownQueueIndex];
	}

	public function start() {
		Thread.create(threadEntry);
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
		var inShutdown = false;
		state = CheckingQueues;
		while(true) {
			++numLooped;

			if (checkQueues()) {
				inShutdown = false;
			}

			if (shutdownSemaphore != null) {
				if (inShutdown) {
					semaphore.release();
					break;
				} else {
					inShutdown = true;
					continue;
				}
			}
			state = Waiting;
			semaphore.acquire();
			state = CheckingQueues;
		}
	}

	function threadEntry() {
		queueTls.value = queue;
		try {
			loop();
		} catch (e:Dynamic) {
			queueTls.value = null;
			start();
			throw e;
		}
		state = Terminated;
		queueTls.value = null;
		shutdownSemaphore?.release();
	}
}