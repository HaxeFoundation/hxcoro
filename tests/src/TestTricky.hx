class CoroFile {
	public final file:String;

	public function new(file) {
		this.file = file;
	}

	@:coroutine public function write(_) {
		return file;
	}

	@:coroutine public function almostWrite(_) {
		return () -> file;
	}
}

class TestTricky extends atest.Test {
	function testCapturedThis() {
		final file = new CoroFile("value");
		Assert.equals("value", cast run(file.write));
	}

	function testPreviouslyCapturedThis() {
		final file = new CoroFile("value");
		final func : ()->String = cast run(file.almostWrite);
		Assert.equals("value", func());
	}
}