package hxcoro.dispatchers;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import hxcoro.thread.IThreadPool;
import haxe.coro.schedulers.IScheduleObject;

/**
	A dispatcher that dispatches to a thread pool.
**/
class ThreadPoolDispatcher implements IDispatcher {
	final pool : IThreadPool;

	/**
		Creates a new `ThreadPoolDispatcher` using `pool` as a thread pool.
	**/
	public function new(pool:IThreadPool) {
		this.pool = pool;
	}

	/**
		@see `IDispatcher.dispatch`
	**/
	public function dispatch(obj:IScheduleObject) {
		pool.run(obj);
	}

	/**
		@see `IDispatcher.shutdown
	**/
	public function shutdown() {
		pool.shutdown();
	}
}