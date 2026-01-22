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
		queue = new WorkStealingQueue();
		activity = new WorkerActivity(threadsCount);
		pool = [for(i in 0...threadsCount) new Worker(cond, i + 1, activity)];
		final queues = [queue].concat([for (worker in pool) worker.queue]);
		final queues = Vector.fromArrayCopy(queues);
		for (worker in pool) {
			worker.setQueues(queues);
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
		// See bottom of `Worker.loop` for details why this is important.
		activity.eventAdded = true;
		// If no one holds onto the condition, notify everyone.
		if (cond.tryAcquire()) {
			cond.broadcast();
			cond.release();
		} else {
			// TODO: remove this and find a better solution
			cond.acquire();
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
}

private class ShutdownException extends ThreadPoolException {}

private class Worker {
	var thread:Thread;
	public final queue:DispatchQueue;

	var queues:Null<Vector<DispatchQueue>>;
	var shutdownCallback:Null<() -> Void>;
	final cond:Condition;
	final ownQueueIndex:Int;
	final activity:WorkerActivity;

	public function new(cond:Condition, ownQueueIndex:Int, activity:WorkerActivity) {
		queue = new WorkStealingQueue();
		this.cond = cond;
		this.ownQueueIndex = ownQueueIndex;
		this.activity = activity;
	}

	public function setQueues(queues:Vector<DispatchQueue>) {
		this.queues = queues;
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
				if (activity.activeWorkers == 1 && activity.eventAdded) {
					// If we're the last worker and this flag is true, there's a chance that the `run` function just
					// los the acquire race against us. In this case we unset the flag and loop once more. Note that
					// it doesn't matter if we win or lose the race on eventAdded because there will be an event in
					// a queue anyway if `run` did indeed run.
					activity.eventAdded = false;
					cond.release();
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
		shutdownCallback();
	}
}