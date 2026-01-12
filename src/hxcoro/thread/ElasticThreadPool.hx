package hxcoro.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

#error "This class doesn't work properly at the moment"

import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;
import sys.thread.Lock;
import haxe.coro.schedulers.IScheduleObject;

/**
	Thread pool with a varying amount of threads.
	A new thread is spawned every time a task is submitted while all existing
	threads are busy.
**/
class ElasticThreadPool implements IThreadPool {
	/* Amount of alive threads in this pool. */
	public var threadsCount(get,null):Int;
	/* Maximum amount of threads in this pool. */
	public var maxThreadsCount:Int;
	/** Indicates if `shutdown` method of this pool has been called. */
	public var isShutdown(get,never):Bool;
	var _isShutdown = false;
	function get_isShutdown():Bool return _isShutdown;

	final pool:Array<Worker> = [];
	final queue = new Deque<IScheduleObject>();
	final mutex = new Mutex();
	final threadTimeout:Float;

	/**
		Create a new thread pool with `threadsCount` threads.
		If a worker thread does not receive a task for `threadTimeout` seconds it
		is terminated.
	**/
	public function new(maxThreadsCount:Int, threadTimeout:Float = 60):Void {
		if(maxThreadsCount < 1)
			throw new ThreadPoolException('ElasticThreadPool needs maxThreadsCount to be at least 1.');
		this.maxThreadsCount = maxThreadsCount;
		this.threadTimeout = threadTimeout;
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

		mutex.acquire();
		var submitted = false;
		var deadWorker = null;
		for(worker in pool) {
			if(deadWorker == null && worker.dead) {
				deadWorker = worker;
			}
			if(worker.task == null) {
				submitted = true;
				worker.wakeup(obj);
				break;
			}
		}
		if(!submitted) {
			if(deadWorker != null) {
				deadWorker.wakeup(obj);
			} else if(pool.length < maxThreadsCount) {
				var worker = new Worker(queue, threadTimeout);
				pool.push(worker);
				worker.wakeup(obj);
			} else {
				queue.add(obj);
			}
		}
		mutex.release();
	}

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, but no new tasks will
		be accepted.
		Multiple calls to this method have no effect.
	**/
	public function shutdown():Void {
		if(_isShutdown) return;
		mutex.acquire();
		_isShutdown = true;
		for(worker in pool) {
			worker.shutdown();
		}
		mutex.release();
	}

	function get_threadsCount():Int {
		var result = 0;
		for(worker in pool)
			if(!worker.dead)
				++result;
		return result;
	}
}

private class Worker {
	public var task(default,null):Null<IScheduleObject>;
	public var dead(default,null) = false;

	final deathMutex = new Mutex();
	final waiter = new Lock();
	final queue:Deque<IScheduleObject>;
	final timeout:Float;
	var thread:Thread;
	var isShutdown = false;

	public function new(queue:Deque<IScheduleObject>, timeout:Float) {
		this.queue = queue;
		this.timeout = timeout;
		start();
	}

	public function wakeup(task:IScheduleObject) {
		deathMutex.acquire();
		if(dead)
			start();
		this.task = task;
		waiter.release();
		deathMutex.release();
	}

	public function shutdown() {
		isShutdown = true;
		waiter.release();
	}

	function start() {
		dead = false;
		thread = Thread.create(loop);
	}

	function loop() {
		try {
			while(waiter.wait(timeout)) {
				switch task {
					case null:
						if(isShutdown)
							break;
					case obj:
						obj.onSchedule();
						//if more tasks were added while all threads were busy
						while(true) {
							switch queue.pop(false) {
								case null: break;
								case obj: obj.onSchedule();
							}
						}
						task = null;
				}
			}
			deathMutex.acquire();
			//in case a task was submitted right after the lock timed out
			if(task != null)
				start()
			else
				dead = true;
			deathMutex.release();
		} catch(e) {
			task = null;
			start();
			throw e;
		}
	}
}