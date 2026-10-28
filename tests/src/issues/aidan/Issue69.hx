package issues.aidan;

import atest.Assert;

private interface IFoo {
    @:coroutine function bar():Void;
}

private class Foo implements IFoo {
    public function new() {}

    @:coroutine public function bar() {
        yield();
    }
}

class Issue69 extends atest.Test {
    public function test() {
        run((_) -> {
            final f : IFoo = new Foo();

            f.bar();
        });

        Assert.pass();
    }
}