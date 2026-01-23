package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import haxe.ds.Vector;
import sys.thread.Condition;
import sys.thread.Semaphore;
import sys.thread.Tls;
import sys.thread.Thread;
import hxcoro.concurrent.AtomicInt;
import hxcoro.concurrent.BackOff;
import haxe.coro.dispatchers.IDispatchObject;

typedef DispatchQueue = WorkStealingQueue<IDispatchObject>;

class TlsQueue {
	static var tls = new Tls<DispatchQueue>();

	static public inline function get() {
		return tls.value;
	}

	static public function install(queue:DispatchQueue) {
		tls.value = queue;
	}
}

private class WorkerActivity {
	public var activeWorkers:Int;
	public var eventAdded:Bool;

	public function new(activeWorkers:Int) {
		this.activeWorkers = activeWorkers;
		eventAdded = false;
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
	final queue:DispatchQueue;
	final thread:Thread;

	final shutdownCounter = new AtomicInt(0);

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount:Int):Void {
		if(threadsCount < 1)
			throw new ThreadPoolException('FixedThreadPool needs threadsCount to be at least 1.');
		this.threadsCount = threadsCount;
		cond = new Condition();
		thread = Thread.current();
		final queues = Vector.fromArrayCopy([for (_ in 0...threadsCount + 1) new WorkStealingQueue()]);
		queue = queues[0];
		activity = new WorkerActivity(threadsCount);
		pool = [for(i in 0...threadsCount) new Worker(cond, queues, i + 1, activity)];
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
		if (Thread.current() == thread) {
			queue.add(obj);
		} else {
			TlsQueue.get().add(obj);
		}
		// If no one holds onto the condition, notify everyone.
		if (cond.tryAcquire()) {
			cond.broadcast();
			cond.release();
		}
	}

	/**
		@see `IThreadPool.shutdown`
	**/
	public function shutdown(block:Bool = false):Void {
		if(_isShutdown) return;
		_isShutdown = true;
		if (block) {
			shutdownCounter.store(pool.length);
		}

		final semaphore = new Semaphore(0);

		function unlock() {
			semaphore.release();
		}
		for (worker in pool) {
			worker.shutDown(unlock);
		}
		cond.acquire();
		cond.broadcast();
		cond.release();
		if (block) {
			for (_ in pool) {
				semaphore.acquire();
			}
		}
	}

	public function dump() {
		Sys.println("FixedThreadPool");
		Sys.println('\tisShutdown: $isShutdown');
		Sys.println('\tactive workers: ${activity.activeWorkers}/${pool.length}');
		Sys.print('\tqueue 0: ');
		queue.dump();
		for (worker in pool) {
			Sys.print('\tqueue ${@:privateAccess worker.ownQueueIndex}: ');
			worker.queue.dump();
		}
	}
}

private class ShutdownException extends ThreadPoolException {}

/**
	This class represents a worker for a thread pool. Some implementation details are:

	- A worker isn't a thread; instead, it has a thread.
	- If the worker's thread terminates prematurely, a new thread is created.
	- When a thread is created, it installs the worker's queue as a static TLS value. This
	  is what the pool's `run` function adds events to.
	- The worker loops over all queues, starting with its own, to look for events to steal
	  and execute.
	- Once all queues are empty, it waits on the condition variable.
	- If `shutDown` is called, the worker keeps executing events until the queues are empty.
**/
private class Worker {
	public var queue(get, never):DispatchQueue;
	var thread:Thread;

	var shutdownCallback:Null<() -> Void>;
	final cond:Condition;
	final queues:Vector<DispatchQueue>;
	final ownQueueIndex:Int;
	final activity:WorkerActivity;

	public function new(cond:Condition, queues:Vector<DispatchQueue>, ownQueueIndex:Int, activity:WorkerActivity) {
		this.cond = cond;
		this.queues = queues;
		this.ownQueueIndex = ownQueueIndex;
		this.activity = activity;
	}

	function get_queue() {
		return queues[ownQueueIndex];
	}

	public function start() {
		thread = Thread.create(threadEntry);
	}

	public function shutDown(callback:() -> Void) {
		shutdownCallback = callback;
	}

	function loop() {
		var index = ownQueueIndex;
		while(true) {
			var didSomething = false;
			while (true) {
				final queue = queues[index];
				final obj = queue.steal();
				if (obj != null) {
					didSomething = true;
					obj.onDispatch();
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
				continue;
			}
			if (shutdownCallback != null) {
				break;
			}
			// If we did nothing, wait for the condition variable.
			if (cond.tryAcquire()) {
				if (activity.activeWorkers == 1) {
					// TODO: just keep one worker thread alive for now to deal with synchronization failures
					cond.release();
					BackOff.backOff();
					continue;
				}
				// These modifications are fine because we hold onto the cond mutex.
				--activity.activeWorkers;
				cond.wait();
				++activity.activeWorkers;
				cond.release();
			} else {
				BackOff.backOff();
			}
		}
	}

	function threadEntry() {
		TlsQueue.install(queue);
		try {
			loop();
		} catch (e:Dynamic) {
			start();
			throw e;
		}
		cond.acquire();
		--activity.activeWorkers;
		cond.release();
		shutdownCallback();
	}
}