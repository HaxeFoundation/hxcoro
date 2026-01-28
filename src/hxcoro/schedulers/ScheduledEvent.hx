package hxcoro.schedulers;

import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.Int64;

private typedef Lambda = () -> Void;

class ScheduledEvent implements ISchedulerHandle implements IDispatchObject {
	var func:Null<Lambda>;

	public final runTime:Int64;

	var childEvents:Array<IDispatchObject>;

	public function new(func, runTime) {
		this.func = func;
		this.runTime = runTime;
	}

	public function addChildEvent(event:IDispatchObject) {
		childEvents ??= [];
		childEvents.push(event);
	}

	public inline function onDispatch() {
		final func = func;
		if (func != null) {
			this.func = null;
			func();
		}

		if (childEvents != null) {
			final childEvents = childEvents;
			this.childEvents = null;
			for (childEvent in childEvents) {
				childEvent.onDispatch();
			}
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
		func = null;
	}
}