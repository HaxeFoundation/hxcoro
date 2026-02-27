import haxe.coro.Mutex;
import hxcoro.Coro.*;

class TestHoisting extends utest.Test {
    function testLocalVariable() {

        @:coroutine function foo(_) {
            var bar = 7;

            yield();

            return bar;
        }

        Assert.equals(7, run(foo));
    }

    function testModifyingLocalVariable() {
        @:coroutine function foo(_) {
            var bar = 7;

            yield();

            bar *= 2;

            yield();

            return bar;
        }

        Assert.equals(14, run(foo));
    }

    @:coroutine function fooTestArgument(v:Int) {
        yield();

        return v;
    }

    function testArgument() {
        Assert.equals(7, run((_) -> {
            return fooTestArgument(7);
        }));
    }

    function testLocalArgument() {
        Assert.equals(7, run((_) -> {
            @:coroutine function foo(v:Int) {
                yield();

                return v;
            }

            return foo(7);
        }));
    }

    @:coroutine function fooTestModifyingArgument(v:Int) {
        yield();

        v *= 2;

        yield();

        return v;
    }

    function testModifyingArgument() {
        Assert.equals(14, run((_) -> {
            return fooTestModifyingArgument(7);
        }));
    }

    function testModifyingLocalArgument() {
        Assert.equals(14, run((_) -> {
            @:coroutine function foo(v:Int) {
                yield();

                v *= 2;

                yield();

                return v;
            }

            return foo(7);
        }));
    }

    function testCapturingLocal() {
        var i = 0;

        run((_) -> {
            i = 7;
            yield();
            i *= 2;
        });

        Assert.equals(14, i);
    }

    function testMultiHoisting() {
        Assert.equals(14, run((_) -> {

            var i = 0;

            @:coroutine function foo() {
                yield();

                i = 7;
            }

            foo();

            return i * 2;

        }));
    }

    function testLoopHoisting() {
        final expected = [1, 2, 3];
        final actual   = [];
		final mutex    = new Mutex();

        run(node -> {
            for (x in expected) {
                node.async(_ -> {
					mutex.acquire();
                    actual.push(x);
					mutex.release();
                });
            }
        });
		actual.sort(Reflect.compare);
        Assert.same(expected, actual);
    }

    function testUninitialisedVariable() {
        Assert.equals(7, run((_) -> {
            var i;

            yield();

            i = 7;

            yield();

            return i;
        }));
    }

    function testNonSuspendingState() {
        final count    = 10;
        final actual   = [];
        final expected = [ for (i in 0...count) i + 1 ];

        run((_) -> {
            var num = 0;
            while (num++ < count) {
                actual.push(num);
            }
        });

        Assert.same(expected, actual);
    }

    function testVariableWriteInSuspendingCall() {
        final count    = 10;
        final actual   = [];
        final expected = [ for (i in 0...count) i + 1 ];

        @:coroutine function f(v:Int) {
            yield();

            return v;
        }

        run((_) -> {
            var num = 0;
            while (f(num++) < count) {
                actual.push(num);
            }
        });

        Assert.same(expected, actual);
    }
}