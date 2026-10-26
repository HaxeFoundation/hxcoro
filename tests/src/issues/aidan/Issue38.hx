package issues.aidan;

@:coroutine function foo(_:hxcoro.task.ICoroNode) : String {
	return suspend(cont -> {
		cont.resume('Hello, World!', null);
	});
}

class Issue38 extends atest.Test {
	function test() {
		Assert.equals("Hello, World!", run(foo));
	}
}