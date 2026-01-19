package hxcoro.dispatchers;

import hxcoro.schedulers.EventLoopScheduler;
import haxe.coro.schedulers.Scheduler;
import haxe.exceptions.ArgumentException;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IScheduleObject;

final class TrampolineDispatcher extends Dispatcher {
	final s : Scheduler;

	var running : Bool;
	var queue : Null<Array<IScheduleObject>>;

	public function new(scheduler : Scheduler = null) {
		s = scheduler ?? new EventLoopScheduler();

		running = false;
		queue   = null;
	}

	public function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IScheduleObject) {
		if (null == obj) {
			throw new ArgumentException("obj");
		}

		if (false == running) {
			running = true;

			obj.onSchedule();

			if (null == queue) {
				running = false;

				return;
			}

			var next = null;
			while (null != (next = queue.shift())) {
				next.onSchedule();
			}

			running = false;
			queue   = null;

		} else {
			queue ??= [];
			queue.push(obj);
		}
	}
}