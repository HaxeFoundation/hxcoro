package issues.hf;

import haxe.coro.continuations.FunctionContinuation;
import hxcoro.Coro.*;
import hxcoro.CoroRun;
import hxcoro.concurrent.CoroLatch;

class Issue119 extends utest.Test {
	/**
		Verifies that calling a coroutine with a custom `FunctionContinuation` inside
		`suspend` works correctly on both single-threaded and multi-threaded targets.

		Covers both `CancellingContinuation` and `RacingContinuation`: on multi-threaded
		targets the scheduler may fire the inner `yield()` event before both
		`CancellingContinuation.resolve()` and `RacingContinuation.resolve()` are called.
		Previously the continuation was silently dropped and the program would hang.
	**/
	@:timeout(5000)
	function test(async:utest.Async) {
		CoroRun.run(() -> {
			@:coroutine function g() {
				yield();
			}

			@:coroutine function f() {
				final latch = new CoroLatch(1);
				final log = [];

				suspend(cont -> {
					final myCont = new FunctionContinuation(cont.context, (r, e) -> {
						log.push("called");
						latch.arrive(1);
						cont.resume(r, e);
					});
					g(myCont);
				});

				latch.wait();
				Assert.same(["called"], log);
				async.done();
			}

			f();
		});
	}

	/**
		Verifies that the `RacingContinuation` race is handled correctly when `resume()`
		beats `resolve()`.

		`suspend()` wraps `cont` in a `RacingContinuation`. By calling `myCont.callAsync()`
		inside the `suspend` lambda, `myCont.resume()` is dispatched to a worker thread
		which then calls `cont.resume()` (= `RacingContinuation.resume()`) before
		`RacingContinuation.resolve()` runs on the calling thread. Previously this caused
		the continuation to be silently dropped and the program to hang. No
		`CancellingContinuation` is involved in this test.
	**/
	@:timeout(5000)
	function testRacingContinuation(async:utest.Async) {
		CoroRun.run(() -> {
			@:coroutine function f() {
				final log = [];

				suspend(cont -> {
					final myCont = new FunctionContinuation(cont.context, (r, e) -> {
						log.push("called");
						cont.resume(r, e);
					});
					myCont.callAsync();
				});

				Assert.same(["called"], log);
				async.done();
			}

			f();
		});
	}
}
