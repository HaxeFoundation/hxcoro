package issues.aidan;

import atest.Assert;
import haxe.Exception;

@:coroutine function foo() {
	suspend(cont -> {
		cont.resume(null, new Exception("error"));
	});
}

class Issue75 extends atest.Test {
    public function test() {
		var s = "";
		run((_) -> {
			try {
				foo();
			} catch (_:Dynamic) {
				s += 'caught';
			}

			s += 'done';
		});
		Assert.equals("caughtdone", s);
    }
}