package issues.hf;

abstract class C {
	@:coroutine abstract public function f():String;
}

class C2 extends C {
	final s:String;

	public function new(s:String) {
		this.s = s;
	}

	@:coroutine public function f() {
		return s;
	}
}

class Issue30 extends utest.Test {
	function test() {
		Assert.equals("ok", CoroRun.run(new C2("ok").f));
		Assert.equals("ok", CoroRun.run(() -> {
			final c:C = new C2("ok");
			c.f();
		}));
	}
}