package hxcoro.dispatchers;

import hxcoro.schedulers.EventLoopScheduler;
import haxe.coro.schedulers.IScheduler;
import haxe.exceptions.ArgumentException;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;

final class TrampolineDispatcher extends Dispatcher {
	final s : IScheduler;

	var running : Bool;
	var queue : Null<Array<IDispatchObject>>;

	public function new(scheduler : IScheduler = null) {
		s = scheduler ?? new EventLoopScheduler();

		running = false;
		queue   = null;
	}

	public function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IDispatchObject) {
		if (null == obj) {
			throw new ArgumentException("obj");
		}

		if (false == running) {
			running = true;

			obj.onDispatch();

			if (null == queue) {
				running = false;

				return;
			}

			var next = null;
			while (null != (next = queue.shift())) {
				next.onDispatch();
			}

			running = false;
			queue   = null;

		} else {
			queue ??= [];
			queue.push(obj);
		}
	}
}