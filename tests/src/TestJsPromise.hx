import js.lib.Error;
import js.lib.Promise;
import hxcoro.Coro;
import hxcoro.CoroRun.await;
import hxcoro.CoroRun.promise;

class TestJsPromise extends atest.Test {
	function testAwait() {
		var p = Promise.resolve(41);
		final result = await(promise(() -> {
			var x = await(p);
			return x + 1;
		}));
		Assert.equals(42, result);
	}

	function testPromise() {
		final result = await(promise(() -> 42));
		Assert.equals(42, result);
	}

	function testYieldingPromise() {
		final result = await(promise(() -> {
			Coro.yield();
			42;
		}));
		Assert.equals(42, result);
	}

	function testAsyncAwait() {
		var p1 = Promise.resolve(41);
		final result = await(promise(() -> {
			var x = await(p1);
			return x + 1;
		}));
		Assert.equals(42, result);
	}

	function testAwaitRejected() {
		// Reject with a haxe.Exception rather than a raw string.
		// On JS, coroutine catch blocks call .unwrap() on the caught
		// value, which crashes for raw (non-object) rejection values.
		var p:js.lib.Promise<Int> = new js.lib.Promise((_, reject) -> reject(new haxe.Exception("oh no")));
		var caughtMsg:String = null;
		try {
			await(promise(() -> {
				var x = await(p);
				return x + 1;
			}));
		} catch (e:haxe.Exception) {
			caughtMsg = e.message;
		}
		Assert.notNull(caughtMsg);
		Assert.equals("oh no", caughtMsg);
	}

	function testThrowInPromise() {
		var p = promise(() -> throw new Error("oh no"));
		var caughtError:Dynamic = null;
		try {
			await(p);
		} catch (e:Dynamic) {
			caughtError = e;
		}
		Assert.notNull(caughtError);
		Assert.isOfType(caughtError, Error);
		Assert.equals("oh no", (caughtError : Error).message);
	}
}
