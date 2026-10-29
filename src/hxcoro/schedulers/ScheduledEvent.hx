package hxcoro.schedulers;

import haxe.Exception;
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

		Dispatching can throw, e.g. with a `TrampolineDispatcher`, which runs the continuation right
		away. The exception then propagates immediately, and the child events that were not
		dispatched yet are passed to `requeue` so that the scheduler can dispatch them later
		instead of losing them.
	**/
	public function dispatch(requeue:ScheduledEvent -> Void) {
		final childEvents = childEvents;
		this.childEvents = null;
		var nextChild = 0;
		try {
			final cont = cont;
			if (cont != null) {
				cont.context.dispatchOrCall(this);
			}
			if (childEvents != null) {
				while (nextChild < childEvents.length) {
					childEvents[nextChild++].dispatch(requeue);
				}
			}
		} catch (e:Exception) {
			if (childEvents != null) {
				for (i in nextChild...childEvents.length) {
					requeue(childEvents[i]);
				}
			}
			throw e;
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
		Cancels this event so that its continuation is not resumed. Child events are not affected.
	**/
	public function close() {
		cont = null;
	}
}