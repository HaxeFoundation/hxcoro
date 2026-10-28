package hxcoro.schedulers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.Int64;

private typedef Lambda = () -> Void;

/**
	A continuation that is due to be resumed at `runTime`, used by the heap-based schedulers.
**/
class ScheduledEvent implements ISchedulerHandle implements IDispatchObject {
	/**
		The time at which this event is due.
	**/
	public final runTime:Int64;
	/**
		The next event, which schedulers use to chain events into a list.
	**/
	public var next:Null<ScheduledEvent>;

	var cont:Null<IContinuation<Any>>;
	var childEvents:Null<Array<ScheduledEvent>>;

	public function new(cont, runTime) {
		this.cont = cont;
		this.runTime = runTime;
	}

	/**
		Attaches `event` to this event so that it is dispatched together with it.
	**/
	public function addChildEvent(event:ScheduledEvent) {
		childEvents ??= [];
		childEvents.push(event);
	}

	/**
		Dispatches the continuation of this event unless it was closed, then dispatches all child events.
	**/
	public function dispatch() {
		final cont = cont;
		if (cont != null) {
			cont.context.dispatchOrCall(this);
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

	/**
		Calls `f` on this event and then on each of its child events. The child events are
		removed from this event, so later calls don't visit them again.
	**/
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

	/**
		Cancels this event so that its continuation is not resumed. Child events are not affected.
	**/
	public function close() {
		cont = null;
	}
}