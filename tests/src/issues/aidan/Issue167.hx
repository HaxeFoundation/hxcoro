package issues.aidan;

using issues.aidan.Issue167.Foo;

private class Foo {
	@:coroutine public static function bar(s:String) {
		yield();

		return s;
	}
}

class Issue167 extends atest.Test {
	function test() {
		Assert.equals("test", run((_) -> {
			"test".bar();
		}));
	}
}