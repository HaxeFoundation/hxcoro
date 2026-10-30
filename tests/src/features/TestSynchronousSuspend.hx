package features;

import haxe.Exception;
import haxe.coro.context.Context;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.dispatchers.SelfDispatcher;
import hxcoro.Coro.*;
import hxcoro.run.Setup;
import hxcoro.schedulers.VirtualTimeScheduler;

using hxcoro.run.ContextRun;

private class CountingDispatcher extends SelfDispatcher {
	public var count = 0;

	override function dispatch(obj:IDispatchObject) {
		count++;
		super.dispatch(obj);
	}
}

/**
	Verifies that `suspend` and `suspendCancellable` don't go through the dispatcher
	if the continuation is resumed before the suspending function returns.
**/
class TestSynchronousSuspend extends atest.Test {
	function runCounting(f:(context:Context, done:(error:Null<Exception>) -> Void) -> Void) {
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new CountingDispatcher(scheduler);
		final context = Setup.defaultContext.with(dispatcher);
		var resumed = false;
		var error = null;
		f(context, e -> {
			resumed = true;
			error = e;
		});
		while (!resumed) {
			scheduler.loop(Once);
		}
		return {count: dispatcher.count, error: error};
	}

	function testSuspend() {
		@:coroutine function f() {
			return suspend(cont -> cont.resume(1, null));
		}
		var result = -1;
		final outcome = runCounting((context, done) -> f(new FunctionContinuation(context, (r, e) -> {
			result = r;
			done(e);
		})));
		Assert.equals(0, outcome.count);
		Assert.isNull(outcome.error);
		Assert.equals(1, result);
	}

	function testSuspendCancellable() {
		@:coroutine function f() {
			return suspendCancellable(cont -> {
				cont.resume(1, null);
				return null;
			});
		}
		var result = -1;
		final outcome = runCounting((context, done) -> f(new FunctionContinuation(context, (r, e) -> {
			result = r;
			done(e);
		})));
		Assert.equals(0, outcome.count);
		Assert.isNull(outcome.error);
		Assert.equals(1, result);
	}

	function testSuspendThrows() {
		@:coroutine function f() {
			suspend(cont -> cont.resume(null, new Exception("foo")));
			suspendCancellable(cont -> {
				cont.resume(null, null);
				return null;
			});
		}
		final outcome = runCounting((context, done) -> f(new FunctionContinuation(context, (_, e) -> done(e))));
		Assert.equals(0, outcome.count);
		Assert.equals("foo", outcome.error?.message);
	}

	function testActualSuspensionDispatches() {
		@:coroutine function f() {
			delay(10);
		}
		final outcome = runCounting((context, done) -> f(new FunctionContinuation(context, (_, e) -> done(e))));
		Assert.isTrue(outcome.count > 0);
		Assert.isNull(outcome.error);
	}
}
