package hxcoro.dispatchers;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import hxcoro.thread.IThreadPool;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.schedulers.IScheduler;

/**
	A dispatcher that dispatches to a thread pool.
**/
class ThreadPoolDispatcher extends Dispatcher {
	final pool : IThreadPool;

	final s : IScheduler;

	/**
		Creates a new `ThreadPoolDispatcher` using `pool` as a thread pool.
	**/
	public function new(scheduler:IScheduler, pool:IThreadPool) {
		this.pool = pool;
		this.s = scheduler;
	}

	/**
		@see `IDispatcher.dispatch`
	**/
	public function dispatch(obj:IDispatchObject) {
		pool.run(obj);
	}

	function get_scheduler() {
		return s;
	}
}