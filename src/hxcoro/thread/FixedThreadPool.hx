package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import haxe.ds.Vector;
import sys.thread.Condition;
import sys.thread.Semaphore;
import sys.thread.Tls;
import sys.thread.Thread;
import hxcoro.concurrent.BackOff;
import haxe.coro.dispatchers.IDispatchObject;

typedef DispatchQueue = WorkStealingQueue<IDispatchObject>;

private class WorkerActivity {
	public var activeWorkers:Int;
	public var availableWorkers:Int;

	public function new(activeWorkers:Int) {
		this.activeWorkers = activeWorkers;
		this.availableWorkers = activeWorkers;
	}
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
		@see `IThreadPool.isShutdown`
	**/
	public var isShutdown(get,never):Bool;
	var _isShutdown = false;
	function get_isShutdown():Bool return _isShutdown;

	final cond:Condition;
	final pool:Array<Worker>;
	final activity:WorkerActivity;
	final queueTls:Tls<DispatchQueue>;

	var hadMissedEventPing:Bool;

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount:Int):Void {
		if(threadsCount < 1)
			throw new ThreadPoolException('FixedThreadPool needs threadsCount to be at least 1.');
		hadMissedEventPing = false;
		this.threadsCount = threadsCount;
		cond = new Condition();
		queueTls = new Tls();
		final queues = Vector.fromArrayCopy([for (_ in 0...threadsCount + 1) new WorkStealingQueue()]);
		queueTls.value = queues[0];
		activity = new WorkerActivity(threadsCount);
		pool = [for(i in 0...threadsCount) new Worker(cond, queueTls, queues, i + 1, activity)];
		for (worker in pool) {
			worker.start();
		}
	}

	/**
		@see `IThreadPool.run`
	**/
	public function run(obj:IDispatchObject):Void {
		if(_isShutdown) {
			throw new ThreadPoolException('Task is rejected. Thread pool is shut down.');
		}
		if(obj == null) {
			throw new ThreadPoolException('Task to run must not be null.');
		}
		queueTls.value.add(obj);
		// If no one holds onto the condition, notify everyone.
		if (cond.tryAcquire()) {
			cond.signal();
			cond.release();
		} else {
			// If we lose the race, set this flag so we can be sure that somebody
			// gets notified in the `ping` function.
			hadMissedEventPing = true;
		}
	}

	public function ping() {
		if (hadMissedEventPing && cond.tryAcquire()) {
			hadMissedEventPing = false;
			cond.signal();
			cond.release();
		}
	}

	/**
		@see `IThreadPool.shutdown`
	**/
	public function shutdown(block:Bool = false):Void {
		if(_isShutdown) return;
		_isShutdown = true;

		final shutdownSemaphore = new Semaphore(0);

		for (worker in pool) {
			worker.shutDown(shutdownSemaphore);
		}
		cond.acquire();
		cond.broadcast();
		cond.release();
		if (block) {
			for (worker in pool) {
				shutdownSemaphore.acquire();
			}
		}
	}

	public function dump() {
		Sys.println("FixedThreadPool");
		Sys.println('\tisShutdown: $isShutdown');
		var totalDispatches = 0i64;
		var totalLoops = 0i64;
		for (worker in pool) {
			totalDispatches += worker.numDispatched;
			totalLoops += worker.numLooped;
		}
		Sys.println('\ttotal worker loops: $totalLoops');
		Sys.println('\ttotal worker dispatches: $totalDispatches');
		Sys.println('\tworkers (active/available/total): ${activity.activeWorkers}/${activity.availableWorkers}/${pool.length}');
		Sys.print('\tqueue 0: ');
		queueTls.value.dump();
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
	var thread:Thread;

	var shutdownSemaphore:Null<Semaphore>;
	final cond:Condition;
	final queues:Vector<DispatchQueue>;
	final ownQueueIndex:Int;
	final activity:WorkerActivity;
	final queueTls:Tls<DispatchQueue>;

	public function new(cond:Condition, queueTls:Tls<DispatchQueue>, queues:Vector<DispatchQueue>, ownQueueIndex:Int, activity:WorkerActivity) {
		this.cond = cond;
		this.queues = queues;
		this.ownQueueIndex = ownQueueIndex;
		this.activity = activity;
		this.queueTls = queueTls;
		numDispatched = 0;
		numLooped = 0;
		state = Created;
	}

	function get_queue() {
		return queues[ownQueueIndex];
	}

	public function start() {
		thread = Thread.create(threadEntry);
	}

	public function shutDown(shutdownSemaphore:Semaphore) {
		this.shutdownSemaphore = shutdownSemaphore;
	}

	function loop() {
		var index = ownQueueIndex;
		var inShutdown = false;
		state = CheckingQueues;
		while(true) {
			var didSomething = false;
			++numLooped;
			while (true) {
				final queue = queues[index];
				final obj = queue.steal();
				if (obj != null) {
					didSomething = true;
					state = Working;
					++numDispatched;
					obj.onDispatch();
					state = CheckingQueues;
					index = ownQueueIndex;
					break;
				}
				if (index == queues.length - 1) {
					index = 0;
				} else {
					++index;
				}
				if (index == ownQueueIndex) {
					break;
				}
			}
			// index == ownQueueIndex here
			if (didSomething) {
				inShutdown = false;
				continue;
			}
			// If we did nothing, wait for the condition variable.
			if (cond.tryAcquire()) {
				if (shutdownSemaphore != null) {
					if (inShutdown) {
						--activity.activeWorkers;
						--activity.availableWorkers;
						cond.broadcast();
						cond.release();
						break;
					} else {
						inShutdown = true;
						cond.broadcast();
						cond.release();
						continue;
					}
				}
				// These modifications are fine because we hold onto the cond mutex.
				--activity.activeWorkers;
				state = Waiting;
				// If we get here we know for sure that there's nothing in our own queue
				// at the moment, so we can reset it.
				queue.reset();
				cond.wait();
				state = CheckingQueues;
				++activity.activeWorkers;
				cond.release();
			} else {
				BackOff.backOff();
			}
		}
	}

	function threadEntry() {
		queueTls.value = queue;
		try {
			loop();
		} catch (e:Dynamic) {
			start();
			throw e;
		}
		state = Terminated;
		shutdownSemaphore.release();
	}
}