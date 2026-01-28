package haxe.coro;

import haxe.coro.context.Context;

class CoroIntrinsics {
	@:coroutine @:coroutine.transformed
	static public function getContext(cont:IContinuation<Any>):SuspensionResult<Context> {
		return ImmediateSuspensionResult.withResult(cont.context);
	}
}