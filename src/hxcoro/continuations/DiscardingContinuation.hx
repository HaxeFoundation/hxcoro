package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;

/**
	Continuation wrapper that resumes the wrapped continuation without a result or an error.
**/
class DiscardingContinuation<T> implements IContinuation<T> {
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
