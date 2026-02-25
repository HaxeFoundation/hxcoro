package directthrow;

import haxe.Exception;

/** A coroutine that throws immediately without any suspension point. **/
@:coroutine function thrower() {
	throw new Exception("direct throw");
}

/** A coroutine that calls thrower() without suspending first. **/
@:coroutine function caller() {
	thrower();
}

/** A plain sync wrapper so the call chain has a non-coro bottom frame. **/
function entry() {
	CoroRun.run(_ -> caller());
}
