package foobarbaz;

import haxe.Exception;

@:coroutine function baz() {
	throw new Exception('hello');
}

@:coroutine function bar() {
	yield();
	baz();
}

@:coroutine function foo() {
	bar();
}
