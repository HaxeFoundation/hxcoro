import haxe.Exception;
import hxcoro.schedulers.VirtualTimeScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;

class TestBasic extends atest.Test {
	function testSimple() {
		Assert.equals(42, run(@:coroutine function run(_) {
			return simple(42);
		}));
	}

	function testErrorDirect() {
		Assert.raises(() -> run(error), String);
	}

	function testErrorPropagation() {
		@:coroutine function propagate(node) {
			error(node);
		}

		Assert.raises(() -> run(propagate), String);
	}

	function testResumeWithError() {
		@:coroutine function foo(_) {
			suspend(cont -> {
				cont.resume(null, new Exception(""));
			});
		}

		Assert.raises(() -> run(foo), Exception);
	}

	function testUnnamedLocalCoroutines() {
		final c1 = @:coroutine function (_) {
			yield();

			return 10;
		};

		Assert.equals(10, run(c1));
	}

	function testLocalTypeParameters() {
		run(@:coroutine function f<T>(_):T {
			return null;
		});
		Assert.pass(); // The test is that this doesn't cause an unbound type parameter
	}

	#if sys

	function testDelay() {
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).with(dispatcher).createTask(_ -> {
			delay(500);
		});

		task.start();

		scheduler.advanceTo(499);
		Assert.isTrue(task.isActive());

		scheduler.advanceTo(500);
		Assert.isFalse(task.isActive());
	}

	#end

	@:coroutine static function simple(arg:Int):Int {
		return arg;
	}

	@:coroutine static function error(_) {
		throw "nope";
	}
}
