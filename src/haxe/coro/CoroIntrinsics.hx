package haxe.coro;

class CoroIntrinsics {
	@:coroutine static public function getContext() {
		return hxcoro.Coro.suspend(cont -> cont.resume(cont.context, null));
	}
}