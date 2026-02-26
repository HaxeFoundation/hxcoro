package issues.hf;

import hxcoro.CoroRun;
import hxcoro.Coro.*;

private class Parent {
	public var log:Array<String>;

	public function new() {
		log = [];
	}

	@:coroutine public function test() {
		log.push("Parent.test() 1");
		yield();
		log.push("Parent.test() 2");
	}
}

private class Child extends Parent {
	@:coroutine override function test() {
		log.push("Child.test() 1");
		super.test();
		log.push("Child.test() 2");
		yield();
		super.test();
		log.push("Child.test() 3");
	}
}

class Issue95 extends utest.Test {
	public function test() {
		final child = new Child();
		run((_) -> child.test());
		Assert.same([
			"Child.test() 1",
			"Parent.test() 1",
			"Parent.test() 2",
			"Child.test() 2",
			"Parent.test() 1",
			"Parent.test() 2",
			"Child.test() 3"
		], child.log);
	}
}