package catchrethrow;

import haxe.Exception;

@:coroutine function thrower() {
	throw new Exception("original");
}

@:coroutine function catcher() {
	yield();
	try {
		thrower();
	} catch (e:Exception) {
		throw e; // rethrow preserving the original exception (and its stack)
	}
}

function entry() {
	CoroRun.run(_ -> catcher());
}
