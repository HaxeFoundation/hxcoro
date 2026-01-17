package hxcoro.dispatchers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IScheduleObject;
import hxcoro.schedulers.EventLoopScheduler;

class EventLoopDispatcher extends Dispatcher {
	final scheduler : EventLoopScheduler;
	
	public function new(scheduler:EventLoopScheduler) {
		this.scheduler = scheduler;
	}

	public function dispatch(obj:IScheduleObject) {
		scheduler.scheduleObject(obj);
	}
}