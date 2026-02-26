package issues.aidan;

import utest.Assert;

class Issue61 extends utest.Test {
	public function test() {
		run(foo);
	}

    @:coroutine function foo(_) {
        var a = 2;
        yield();
        Assert.equals(2, a);

        var a = 1;
        yield();
        Assert.equals(1, a);
    }
}