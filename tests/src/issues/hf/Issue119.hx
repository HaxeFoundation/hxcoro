package issues.hf;

import haxe.coro.continuations.FunctionContinuation;
import hxcoro.Coro.*;
import hxcoro.CoroRun;
import hxcoro.concurrent.CoroLatch;

class Issue119 extends utest.Test {
	/**
		Verifies that calling a coroutine with a custom `FunctionContinuation` inside
		`suspend` works correctly on both single-threaded and multi-threaded targets.
		On multi-threaded targets the scheduler can fire the inner `yield` event before
		`CancellingContinuation.resolve()` is called, which previously caused the
		continuation to be silently dropped and the program to hang.
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
}
