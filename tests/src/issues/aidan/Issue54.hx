package issues.aidan;

@:coroutine function suspendThenThrow() {
	yield();
	throw "fail";
}

@:coroutine function f(_) {
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