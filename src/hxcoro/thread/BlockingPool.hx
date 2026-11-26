package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.coro.dispatchers.IDispatchObject;
import sys.thread.Mutex;

/**
	A context element that holds the thread pool on which `hxcoro.Coro.blocking` runs its
	functions. The pool is created when it is first used.
**/
class BlockingPool implements IElement<BlockingPool> {
	/**
		The key under which this element is stored in a `Context`.
	**/
	static public final key = new Key<BlockingPool>("BlockingPool");

	/**
		The number of threads of a `BlockingPool` that is created without an explicit number.
	**/
	static public inline final DEFAULT_THREADS = 16;

	final numThreads:Int;
	final mutex:Mutex;
	var pool:Null<IThreadPool>;
	var isShutDown:Bool;

	public function new(numThreads:Int = DEFAULT_THREADS) {
		this.numThreads = numThreads;
		mutex = new Mutex();
		pool = null;
		isShutDown = false;
	}

	public function getKey() {
		return key;
	}

	/**
		Runs `obj` on a thread of this pool.

		Throws `ThreadPoolException` if the pool has been shut down.
	**/
	public function run(obj:IDispatchObject) {
		mutex.acquire();
		var pool = pool;
		if (pool == null) {
			if (isShutDown) {
				mutex.release();
				throw new ThreadPoolException("The blocking pool has been shut down.");
			}
			this.pool = pool = new FixedThreadPool(numThreads);
		}
		mutex.release();
		pool.run(obj);
	}

	/**
		Shuts down the pool and blocks until its threads have exited, which includes waiting
		for the functions that are still running. Has no effect if called again.
	**/
	public function shutDown() {
		mutex.acquire();
		isShutDown = true;
		final pool = pool;
		mutex.release();
		if (pool != null) {
			pool.shutDown(true);
		}
	}
}
