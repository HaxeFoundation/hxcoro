package hxcoro.thread;

import haxe.coro.dispatchers.IScheduleObject;
#if (!target.threaded)
#error "This class is not available on this target"
#end

import sys.thread.Condition;
import sys.thread.Deque;
import sys.thread.Thread;
import hxcoro.concurrent.AtomicInt;
import haxe.coro.dispatchers.IScheduleObject;

/**
	Thread pool with a constant amount of threads.
	Threads in the pool will exist until the pool is explicitly shut down.
**/
class FixedThreadPool implements IThreadPool implements IScheduleObject {
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

	final pool:Array<Worker>;
	final queue = new Deque<IScheduleObject>();
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
		pool = [for(i in 0...threadsCount) new Worker(queue)];
	}

	/**
		@see `IThreadPool.run`
	**/
	public function run(obj:IScheduleObject):Void {
		if(_isShutdown)
			throw new ThreadPoolException('Task is rejected. Thread pool is shut down.');
		if(obj == null)
			throw new ThreadPoolException('Task to run must not be null.');
		queue.add(obj);
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
		for(_ in pool) {
			queue.add(this);
		}
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
		@see `IScheduleObject.onSchedule`
	**/
	public function onSchedule():Void {
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
	final queue:Deque<Null<IScheduleObject>>;

	public function new(queue:Deque<Null<IScheduleObject>>) {
		this.queue = queue;
		thread = Thread.create(loop);
	}

	function loop() {
		try {
			while(true) {
				var task = queue.pop(true);
				task.onSchedule();
			}
		} catch(_:ShutdownException) {
		} catch(e) {
			thread = Thread.create(loop);
			throw e;
		}
	}
}