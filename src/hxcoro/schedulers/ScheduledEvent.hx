package hxcoro.schedulers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.Int64;

private typedef Lambda = () -> Void;

class ScheduledEvent implements ISchedulerHandle implements IDispatchObject {
	public final runTime:Int64;

	var cont:Null<IContinuation<Any>>;
	var childEvents:Array<ScheduledEvent>;

	public function new(cont, runTime) {
		this.cont = cont;
		this.runTime = runTime;
	}

	public function addChildEvent(event:ScheduledEvent) {
		childEvents ??= [];
		childEvents.push(event);
	}

	public function dispatch() {
		final cont = cont;
		if (cont != null) {
			cont.context.get(Dispatcher).dispatch(this);
		}
		if (childEvents != null) {
			final childEvents = childEvents;
			this.childEvents = null;
			for (childEvent in childEvents) {
				childEvent.dispatch();
			}
		}
	}

	public inline function onDispatch() {
		final cont = cont;
		if (cont != null) {
			this.cont = null;
			cont.resume(null, null);
		}
	}

	public function iterateEvents(f:IDispatchObject->Void) {
		final childEvents = childEvents;
		this.childEvents = null;
		f(this);
		if (childEvents != null) {
			for (childEvent in childEvents) {
				f(childEvent);
			}
		}
	}

	public function close() {
		cont = null;
	}
}