package issues.hf;

import hxcoro.task.ICoroNode;

abstract class C {
	@:coroutine abstract public function f(node:ICoroNode):String;
}

class C2 extends C {
	final s:String;

	public function new(s:String) {
		this.s = s;
	}

	@:coroutine public function f(_) {
		return s;
	}
}

class Issue30 extends utest.Test {
	function test() {
		Assert.equals("ok", run(new C2("ok").f));
		Assert.equals("ok", run((node) -> {
			final c:C = new C2("ok");
			c.f(node);
		}));
	}
}