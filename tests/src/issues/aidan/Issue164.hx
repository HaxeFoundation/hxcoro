package issues.aidan;

class Issue164 extends utest.Test {
	@:coroutine function f(_) {
		{};
		throw "this won't run";
	}

	function test() {
		Assert.raises(() -> CoroRun.run(f), String);
	}
}