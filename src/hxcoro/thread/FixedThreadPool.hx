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

private abstract Storage<T>(Vector<T>) {
	public var length(get, never):Int;

	public inline function new(vector:Vector<T>) {
		this = vector;
	}

	public inline function get_length() {
		return this.length;
	}

	@:arrayAccess public inline function get(i:Int) {
		// `& (x - 1)` is the same as `% x` when x is a power of two
		return this[i & (this.length - 1)];
	}

	@:arrayAccess public inline function set(i:Int, v:T) {
		return this[i & (this.length - 1)] = v;
	}
}

class WsQueue<T> {
	final read:AtomicInt;
	final write:AtomicInt;
	var storage:Storage<T>;

	public function new() {
		read = new AtomicInt(0);
		write = new AtomicInt(0);
		storage = new Storage(new Vector(16));
	}

	public inline function sizeApprox() {
		return write.load() - read.load();
	}

	function resize(from:Int, to:Int) {
		final newStorage = new Storage(new Vector(storage.length << 1));
		for (i in from...to) {
			newStorage[i] = storage[i];
		}
		storage = newStorage;
	}

	public function add(x:T) {
		final w = write.load();
		final r = read.load();
		final sizeNeeded = w - r;
		if (sizeNeeded >= storage.length - 1) {
			resize(r, w);
		}
		storage[w] = x;
		write.add(1);
	}

	public function steal() {
		while (true) {
			final r = read.load();
			final w = write.load();
			final size = w - r;
			if (size <= 0) {
				return null;
			}
			final storage = storage;
			final v = storage[r];
			if (read.compareExchange(r, r + 1) == r) {
				return v;
			} else {
				// loop to try again
			}
		}
	}
}

class TlsQueue<T> {
	final data:WsQueue<T>;
	public function new() {
		data = new WsQueue();
	}

	public function push(v:T) {
		data.add(v);
	}

	public function pop() {
		return data.steal();
	}

	static public function get<T>() {
		static var tls = new Tls<TlsQueue<T>>();
		return tls.value ??= new TlsQueue();
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
	final queue:WsQueue<IDispatchObject>;
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
		pool = [for(i in 0...threadsCount) new Worker(cond)];
		queue = new WsQueue();
		thread = Thread.current();
		final queues = [queue].concat([for (worker in pool) worker.queue]);
		for (worker in pool) {
			worker.setQueues(Vector.fromArrayCopy(queues));
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
			TlsQueue.get().push(obj);
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
	public final queue:WsQueue<IDispatchObject>;

	var queues:Null<Vector<WsQueue<IDispatchObject>>>;
	var shutdownRequested:Bool;
	final cond:Condition;

	public function new(cond:Condition) {
		queue = new WsQueue();
		this.cond = cond;
		shutdownRequested = false;
	}

	public function setQueues(queues:Vector<WsQueue<IDispatchObject>>) {
		this.queues = queues;
	}

	public function start() {
		thread = Thread.create(loop);
	}

	public function shutDown() {
		shutdownRequested = true;
	}

	function drainTlsQueue() {
		while (true) {
			final obj = TlsQueue.get().pop();
			if (obj == null) {
				break;
			}
			queue.add(obj);
		}
	}

	function loop() {
		var emptyIterations = 0;
		while(true) {
			drainTlsQueue();
			var didSomething = false;
			// TODO: this is silly
			for (queue in queues) {
				final obj = queue.steal();
				if (obj != null) {
					didSomething = true;
					try {
						obj.onDispatch();
					} catch(e:Dynamic) {
						// Need to drain the queue in case there's something there because
						// we're about to terminate the thread.
						drainTlsQueue();
						start();
						throw e;
					}
					break;
				}
			}
			if (didSomething) {
				emptyIterations = 0;
				continue;
			}
			if (shutdownRequested) {
				break;
			}
			// Allow a few idle iterations in order to avoid some traffic on the condition variable.
			if (emptyIterations++ < 3) {
				continue;
			}
			// If we did nothing for a while, wait for the condition variable.
			if (cond.tryAcquire()) {
				cond.wait();
				cond.release();
			}
		}
		cond.acquire();
		cond.broadcast();
		cond.release();
	}
}