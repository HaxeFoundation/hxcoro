package issues.aidan;

@:coroutine function suspendThenThrow() {
	delay(1);
	throw "fail";
}

@:coroutine function f(_:hxcoro.task.ICoroNode) {
	try {
		suspendThenThrow();
		return "wrong";
	} catch (e:Dynamic) {
		return 'caught: $e';
	}
}

class Issue54 extends atest.Test {
	public function test() {
		Assert.equals("caught: fail", run(f));
	}
}