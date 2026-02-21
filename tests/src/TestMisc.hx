import hxcoro.Coro.*;

class TestMisc extends utest.Test {
    function testDebugMetadataLocalFunction() {
        @:coroutine(debug) function foo() {
            yield();
        }

        CoroRun.run(foo);

        Assert.pass();
    }
}