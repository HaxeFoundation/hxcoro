package hxcoro;

import haxe.coro.Coroutine;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import hxcoro.run.Setup;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;
using hxcoro.run.LoopRun;

/**
	Entry points for running coroutines from non-coroutine code.
**/
class CoroRun {
	/**
		Returns a copy of `Setup.defaultContext` with `elements` added, e.g. for use with
		`runWith`.
	**/
	public static function with(...elements:IElement<Any>):Context {
		return Setup.defaultContext.with(...elements);
	}

	/**
		Executes `lambda` in `Setup.defaultContext`, blocking until it returns or throws.
		See `runWith` for details.
	**/
	static public inline function run<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):T {
		return runWith(Setup.defaultContext, lambda#if coro.stack_traces, callPos#end);
	}

	#if js

	/**
		Starts executing coroutine `f` in a new task and returns a `js.lib.Promise` that is
		resolved with its result or rejected with its exception.
	**/
	overload extern static public inline function promise<T>(f:Coroutine<() -> T>):js.lib.Promise<T> {
		return promiseImpl(_ -> f());
	}

	/**
		Starts executing `lambda` in a new task and returns a `js.lib.Promise` that is
		resolved with its result or rejected with its exception.
	**/
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

	/**
		Suspends the current coroutine until `p` settles, then returns its value or throws
		its rejection reason.
	**/
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
	**/
	static public function runWith<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):T {
		final setup = Setup.createDefault();
		final context = setup.adaptContext(context);
		final task = setup.loop.runTask(context, lambda#if coro.stack_traces, callPos#end);
		setup.close();
		return @:privateAccess ContextRun.resolveTask(task);
	}
}