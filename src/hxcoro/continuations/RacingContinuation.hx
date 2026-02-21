package hxcoro.continuations;

import hxcoro.concurrent.AtomicInt;
import haxe.coro.dispatchers.Dispatcher;
import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.IDispatchObject;

private enum abstract State(Int) to Int {
	var Active;
	var Resumed;
	var Resolved;
}

class RacingContinuation<T> extends SuspensionResult<T> implements IContinuation<T> implements IDispatchObject {
	final inputCont:IContinuation<T>;

	var resumeState:AtomicInt;

	public var context(get, never):Context;

	final dispatcher:Dispatcher;

	public function new(inputCont:IContinuation<T>) {
		super(Pending);
		this.inputCont = inputCont;
		resumeState = new AtomicInt(Active);
		dispatcher = context.getOrRaise(Dispatcher);
	}

	inline function get_context() {
		return inputCont.context;
	}

	public function resume(result:T, error:Exception):Void {
		this.result = result;
		this.error = error;
		if (resumeState.compareExchange(Active, Resumed) != Active) {
			dispatcher.dispatch(this);
		}
	}

	public function resolve():Void {
		if (resumeState.compareExchange(Active, Resolved) == Active) {
			state = Pending;
		} else {
			if (error != null) {
				state = Thrown;
			} else {
				state = Returned;
			}
		}
	}

	public function onDispatch() {
		inputCont.resume(result, error);
	}
}
