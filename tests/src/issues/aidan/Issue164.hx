package issues.aidan;

class Issue164 extends atest.Test {
	@:coroutine function f(_:hxcoro.task.ICoroNode) {
		{};
		throw "this won't run";
	}

	function test() {
		Assert.raises(() -> run(f), String);
	}
}