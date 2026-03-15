package issues.hf;

private class C {
	public function new() {	}

	@:coroutine public function map(f:Int->Void) {}
}

class Issue49 extends atest.Test {
	function test() {
		var c = new C();
		run(node -> {
			c.map(i -> {});
		});
		Assert.pass();
	}
}