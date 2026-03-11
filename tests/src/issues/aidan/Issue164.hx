package issues.aidan;

class Issue164 extends atest.Test {
	@:coroutine function f(_) {
		{};
		throw "this won't run";
	}

	function test() {
		Assert.raises(() -> run(f), String);
	}
}