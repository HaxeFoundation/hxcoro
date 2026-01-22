package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import haxe.ds.Vector;
import sys.thread.Condition;
import sys.thread.Tls;
import sys.thread.Thread;
import hxcoro.concurrent.AtomicInt;
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

/**
	Thread pool with a constant amount of threads.
	Threads in the pool will exist until the pool is explicitly shut down.
**/
class FixedThreadPool implements IThreadPool implements IDispatchObject {
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
	final queue:DispatchQueue;
	final thread:Thread;

	final shutdownCounter = new AtomicInt(0);
	#if !neko
	final shutdownCond = new Condition();
	#end

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
		pool = [for(i in 0...threadsCount) new Worker(cond, i + 1)];
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
		// If no one holds onto the condition, notify everyone.
		if (cond.tryAcquire()) {
			cond.broadcast();
			cond.release();
		} else {
			// TODO: I think we have to do something here because the last active
			// worker thread could just have acquired the condition variable in order
			// to wait for it, which would deadlock us.
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
		for (worker in pool) {
			worker.shutDown();
		}
		cond.acquire();
		cond.broadcast();
		cond.release();
		if (block) {
			// TODO: need Condition implementation
			#if !neko
			shutdownCond.acquire();
			while (shutdownCounter.load() > 0) {
				shutdownCond.wait();
			}
			shutdownCond.release();
			#end
		}
	}

	/**
		@see `IDispatchObject.onDispatch`
	**/
	public function onDispatch():Void {
		#if !neko
		shutdownCounter.sub(1);
		shutdownCond.acquire();
		shutdownCond.signal();
		shutdownCond.release();
		#end
		throw new ShutdownException('');
	}
}

private class ShutdownException extends ThreadPoolException {}

private class Worker {
	var thread:Thread;
	public final queue:DispatchQueue;

	var queues:Null<Vector<DispatchQueue>>;
	var shutdownRequested:Bool;
	final cond:Condition;
	final ownQueueIndex:Int;

	public function new(cond:Condition, ownQueueIndex:Int) {
		queue = new WorkStealingQueue();
		this.cond = cond;
		this.ownQueueIndex = ownQueueIndex;
		shutdownRequested = false;
	}

	public function setQueues(queues:Vector<DispatchQueue>) {
		this.queues = queues;
	}

	public function start() {
		thread = Thread.create(threadEntry);
	}

	public function shutDown() {
		shutdownRequested = true;
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
			if (shutdownRequested) {
				break;
			}
			// If we did nothing, wait for the condition variable.
			if (cond.tryAcquire()) {
				cond.signal(); // TODO: shouldn't be here, but maybe deals with the situation mentioned in run
				cond.wait();
				cond.release();
			} else {
				// TODO: needs a real backoff instead of this nonsense
				Sys.sleep(1 / 0xFFFFFFFFu32);
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
		cond.broadcast();
		cond.release();
	}
}