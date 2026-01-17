package hxcoro.dispatchers;

#if (!target.threaded)
#error "This class is not available on this target"
#end

import hxcoro.thread.IThreadPool;
import haxe.coro.dispatchers.IScheduleObject;
import haxe.coro.dispatchers.Dispatcher;

/**
	A dispatcher that dispatches to a thread pool.
**/
class ThreadPoolDispatcher extends Dispatcher implements IDispatcher {
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
}