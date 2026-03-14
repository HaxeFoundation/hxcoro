package issues.aidan;

class Issue165 extends atest.Test {
	@:coroutine function foo(i:haxe.Int64) {
		yield();

		return i;
	}

	function test() {
		Assert.pass();
	}
}