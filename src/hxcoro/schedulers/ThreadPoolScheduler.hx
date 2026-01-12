package hxcoro.schedulers;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import sys.thread.Thread;
import haxe.Int64;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;
import hxcoro.thread.IThreadPool;

private class NoOpHandle implements ISchedulerHandle {
	public function new() {}
	public function close() {}
}

final class ThreadPoolScheduler extends Scheduler {
	final pool : IThreadPool;

	final thread : Thread;

	final eventLoop : EventLoopScheduler;

	public function new(pool) {
		super();

		this.pool      = pool;
		this.eventLoop = new EventLoopScheduler();
		this.thread    = Thread.create(keepAlive);
	}

	public function schedule(ms:Int64, func:()->Void):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		if (0 == ms) {
			pool.run(func);

			return new NoOpHandle();
		}

		return eventLoop.schedule(ms, pool.run.bind(func));
	}

	public function scheduleObject(obj:IScheduleObject):Void {
		pool.run(obj.onSchedule);
	}

	public function now() {
		return eventLoop.now();
	}

	function keepAlive() {
		while (true) {
			eventLoop.run();
		}
	}
}