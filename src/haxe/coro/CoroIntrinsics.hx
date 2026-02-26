package haxe.coro;

import haxe.coro.context.Context;

class CoroIntrinsics {
	@:coroutine(transformed)
	static public function getContext(cont:IContinuation<Any>):SuspensionResult<Context> {
		return SuspensionResult.withResult(cont.context);
	}
}