package hxcoro.schedulers;

import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.Int64;

/**
	A continuation that is due to be resumed at `runTime`, used by the heap-based schedulers.
**/
class ScheduledEvent implements ISchedulerHandle implements IDispatchObject {
	/**
		The time at which this event is due.
	**/
	public final runTime:Int64;

	/**
		The insertion order in the heap, which orders events with the same `runTime`.
	**/
	@:allow(hxcoro.schedulers.MinimumHeap)
	var sequence:Int;

	var cont:Null<IContinuation<Any>>;

	public function new(cont, runTime) {
		this.cont = cont;
		this.runTime = runTime;
		sequence = 0;
	}

	/**
		Dispatches the continuation of this event unless it was closed.
	**/
	public function dispatch() {
		final cont = cont;
		if (cont != null) {
			cont.context.dispatchOrCall(this);
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
		Cancels this event so that its continuation is not resumed.
	**/
	public function close() {
		cont = null;
	}
}
