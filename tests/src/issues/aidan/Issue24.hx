package issues.aidan;

class MyCont {
	public function new() {}

	public function getOrThrow():Any {
		return "foo";
	}
}

@:coroutine
private function await(_) {
	var safe = new MyCont();
	return {
		var this1 = safe.getOrThrow();
		this1;
	};
}

class Issue24 extends atest.Test {
	function test() {
		Assert.equals("foo", run(await));
	}
}