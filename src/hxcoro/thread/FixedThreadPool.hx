package hxcoro.thread;

import haxe.coro.schedulers.IScheduleObject;
#if (!target.threaded)
#error "This class is not available on this target"
#end

import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;

/**
	Thread pool with a constant amount of threads.
	Threads in the pool will exist until the pool is explicitly shut down.
**/
class FixedThreadPool implements IThreadPool implements IScheduleObject {
	/* Amount of threads in this pool. */
	public var threadsCount(get,null):Int;
	function get_threadsCount():Int return threadsCount;

	/** Indicates if `shutdown` method of this pool has been called. */
	public var isShutdown(get,never):Bool;
	var _isShutdown = false;
	function get_isShutdown():Bool return _isShutdown;

	final pool:Array<Worker>;
	final poolMutex = new Mutex();
	final queue = new Deque<IScheduleObject>();

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
		Submit a task to run in a thread.
		Throws an exception if the pool is shut down.
	**/
	public function run(obj:IScheduleObject):Void {
		if(_isShutdown)
			throw new ThreadPoolException('Task is rejected. Thread pool is shut down.');
		if(obj == null)
			throw new ThreadPoolException('Task to run must not be null.');
		queue.add(obj);
	}

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, but no new tasks will
		be accepted.
		Multiple calls to this method have no effect.
	**/
	public function shutdown():Void {
		if(_isShutdown) return;
		_isShutdown = true;
		for(_ in pool) {
			queue.add(this);
		}
	}

	public function onSchedule():Void {
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