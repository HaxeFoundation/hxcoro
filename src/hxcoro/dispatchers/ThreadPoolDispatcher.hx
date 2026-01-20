package hxcoro.dispatchers;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import hxcoro.thread.IThreadPool;
import haxe.coro.dispatchers.IScheduleObject;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.schedulers.Scheduler;

/**
	A dispatcher that dispatches to a thread pool.
**/
class ThreadPoolDispatcher extends Dispatcher implements IDispatcher {
	final pool : IThreadPool;

	final s : Scheduler;

	/**
		Creates a new `ThreadPoolDispatcher` using `pool` as a thread pool.
	**/
	public function new(scheduler:Scheduler, pool:IThreadPool) {
		this.pool = pool;
		this.s = scheduler;
	}

	/**
		@see `IDispatcher.dispatch`
	**/
	public function dispatch(obj:IScheduleObject) {
		pool.run(obj);
	}

	function get_scheduler() {
		return s;
	}
}