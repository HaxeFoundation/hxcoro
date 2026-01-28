package hxcoro.continuations;

import haxe.coro.context.Context;
import haxe.Exception;
import haxe.coro.IContinuation;

typedef ContinuationLambda<T> = (result:T, error:Exception) -> Void;

class FunctionContinuation<T> implements IContinuation<T> {
	public var context(get, null):Context;

	final func:ContinuationLambda<T>;

	public function new(context:Context, func:ContinuationLambda<T>) {
		this.context = context;
		this.func = func;
	}

	function get_context() {
		return context;
	}

	public function resume(result:T, error:Exception) {
		func(result, error);
	}
}