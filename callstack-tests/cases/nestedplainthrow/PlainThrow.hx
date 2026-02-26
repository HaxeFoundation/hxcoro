package nestedplainthrow;

import haxe.Exception;

/** A plain (non-coroutine) function that throws. **/
function thrower() {
	throw new Exception("plain throw from nested async scope");
}

function entry() {
	CoroRun.run(node -> {
		yield();
		node.async(node -> {
			yield();
			node.async(node -> {
				yield();
				thrower();
			});
		});
	});
}
