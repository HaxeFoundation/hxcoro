package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.concurrent.AtomicInt;

private enum abstract State(Int) to Int {
	var Active;
	var Resumed;
	var Resolved;
}

class RacingContinuation<T> extends StackFrameContinuation<T> implements IDispatchObject {
	var resumeState:AtomicInt;

	public function new(cont:IContinuation<T>) {
		super(cont);
		resumeState = new AtomicInt(Active);
	}

	public function resume(result:T, error:Exception):Void {
		this.result = result;
		this.error = error;
		this.state = error == null ? Returned : Thrown;
		if (resumeState.compareExchange(Active, Resumed) != Active) {
			context.dispatchOrCall(this);
		}
	}

	public function resolve():Void {
		if (resumeState.compareExchange(Active, Resolved) == Active) {
			state = Pending;
		} else {
			context.dispatchOrCall(this);
		}
	}

	public function onDispatch() {
		cont.resume(result, error);
	}
}
