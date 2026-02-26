package hxcoro;

import haxe.coro.Coroutine;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import hxcoro.run.Setup;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;
using hxcoro.run.LoopRun;

class CoroRun {
	public static function with(...elements:IElement<Any>):Context {
		return Setup.defaultContext.with(...elements);
	}

	overload extern static public inline function run<T>(lambda:Coroutine<() -> T>#if debug, ?callPos:haxe.PosInfos#end):T {
		return runWith(Setup.defaultContext, _ -> lambda()#if debug, callPos#end);
	}

	overload extern static public inline function run<T>(lambda:NodeLambda<T>#if debug, ?callPos:haxe.PosInfos#end):T {
		return runWith(Setup.defaultContext, lambda#if debug, callPos#end);
	}

	@:deprecated("Use `CoroRun.run` instead")
	static public function runScoped<T>(lambda:NodeLambda<T>#if debug, ?callPos:haxe.PosInfos#end):T {
		return runWith(Setup.defaultContext, lambda#if debug, callPos#end);
	}

	#if js

	overload extern static public inline function promise<T>(f:Coroutine<() -> T>):js.lib.Promise<T> {
		return promiseImpl(_ -> f());
	}

	overload extern static public inline function promise<T>(lambda:NodeLambda<T>):js.lib.Promise<T> {
		return promiseImpl(lambda);
	}

	static function promiseImpl<T>(lambda:NodeLambda<T>) {
		final scheduler = new hxcoro.schedulers.HaxeTimerScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		final task = new Setup(dispatcher).createContext().launchTask(lambda);

		return new js.lib.Promise((resolve, reject) -> {
			task.onCompletion((result, error) -> {
				switch error {
					case null:
						resolve(result);
					case exn:
						reject(exn);
				}
			});
		});
	}

	@:coroutine
	static public function await<T>(p:js.lib.Promise<T>) {
		return suspend(cont -> {
			p.then(
				r -> cont.resume(r, null),
				e -> cont.resume(null, e)
			);
		});
	}

	#end

	/**
		Executes `lambda` in context `context`, blocking until it returns or throws.

		If there exists a `Dispatcher` element in the context, it is ignored. This
		function always installs its own instance of `Dispatcher` into the context
		and uses it to drive execution. The exact dispatcher implementation being
		used depends on the target.

		Each invocation creates its own independent `Setup` (scheduler + dispatcher),
		so separate calls from different threads do not interfere with each other.

		**This function is not re-entrant with respect to its event loop.**  Calling
		`runWith` (or `CoroRun.run`) from inside a coroutine that is itself executing
		under a `runWith` call would require both the outer and the inner call to drive
		the *same* loop concurrently.  On threaded targets this leads to a deadlock:
		both threads end up blocked on the same scheduler semaphore waiting to be
		woken by each other's task completion, but each task completion releases the
		semaphore only once — the signal can be consumed by the wrong thread,
		permanently blocking the other one (the "stolen wakeup" problem).

		Nested coroutine calls should use structured concurrency primitives such as
		`Coro.scope`, `Coro.supervisor`, or child tasks instead.
	**/
	static public function runWith<T>(context:Context, lambda:NodeLambda<T>#if debug, ?callPos:haxe.PosInfos#end):T {
		final setup = Setup.createDefault();
		final context = setup.adaptContext(context);
		final task = setup.loop.runTask(context, lambda#if debug, callPos#end);
		setup.close();
		return @:privateAccess ContextRun.resolveTask(task);
	}
}