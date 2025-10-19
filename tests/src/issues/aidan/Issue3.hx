package issues.aidan;

import haxe.ds.Option;
import haxe.coro.schedulers.VirtualTimeScheduler;
import hxcoro.CoroRun;
import hxcoro.Coro.*;

class Issue3 extends utest.Test {
	var f0_lambda : Coroutine<(?n0 : Int)->Int>;
	var f1_lambda : Coroutine<(n0 : Int, ?n1 : Int)->Int>;
	var f2_lambda : Coroutine<(?n0 : Int)->Null<Int>>;
	var f3_lambda : Coroutine<(?o:Option<Int>)->Option<Int>>;

	function test_default_args() {
		f0_lambda = f0;
		f1_lambda = f1;

		Assert.equals(20, CoroRun.run(() -> f0()));
		Assert.equals(40, CoroRun.run(() -> f0(20)));
		Assert.equals(20, CoroRun.run(() -> f0_lambda()));
		Assert.equals(40, CoroRun.run(() -> f0_lambda(20)));

		Assert.equals(20, CoroRun.run(() -> f1(2)));
		Assert.equals(40, CoroRun.run(() -> f1(2, 20)));
		Assert.equals(20, CoroRun.run(() -> f1_lambda(2)));
		Assert.equals(40, CoroRun.run(() -> f1_lambda(2, 20)));
	}

	function test_optional_args() {
		f2_lambda = f2;
		f3_lambda = f3;

		Assert.equals(null, CoroRun.run(() -> f2()));
		Assert.equals(10, CoroRun.run(() -> f2(10)));
		Assert.equals(null, CoroRun.run(() -> f2_lambda()));
		Assert.equals(10, CoroRun.run(() -> f2_lambda(10)));

		Assert.equals(null, CoroRun.run(() -> f3()));
		Assert.same(Option.None, CoroRun.run(() -> f3(Option.None)));
		Assert.equals(null, CoroRun.run(() -> f3_lambda()));
		Assert.same(Option.None, CoroRun.run(() -> f3_lambda(Option.None)));
	}

	@:coroutine function f0(n0 : Int = 10) {
		yield();

		return n0 * 2;
	}

	@:coroutine function f1(n0 : Int, n1 : Int = 10) {
		yield();

		return n0 * n1;
	}

	@:coroutine function f2(?n0:Int) {
		yield();

		return n0;
	}

	@:coroutine function f3(o:Option<Int> = null) {
		yield();

		return o;
	}
}