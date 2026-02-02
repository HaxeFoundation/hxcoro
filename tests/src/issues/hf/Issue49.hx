package issues.hf;

private class C {
	public function new() {	}

	@:coroutine public function map(f:Int->Void) {}
}

class Issue49 extends utest.Test {
	function test() {
		var c = new C();
		CoroRun.run(node -> {
			c.map(i -> {});
		});
		Assert.pass();
	}
}