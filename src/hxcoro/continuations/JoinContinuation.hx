package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;

/**
	Continuation wrapper used by `ICoroTask.join` that resumes the wrapped continuation
	without a result or an error, whatever it is resumed with.
**/
class JoinContinuation<T> implements IContinuation<T> {
	final cont:IContinuation<Any>;

	public var context(get, never):Context;

	public function new(cont:IContinuation<Any>) {
		this.cont = cont;
	}

	function get_context() {
		return cont.context;
	}

	public function resume(_:Null<T>, _:Null<Exception>) {
		cont.resume(null, null);
	}
}
