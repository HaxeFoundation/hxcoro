package hxcoro;

import haxe.coro.Coroutine;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.EventLoopScheduler;
import hxcoro.schedulers.HaxeTimerScheduler;
import hxcoro.task.NodeLambda;

using hxcoro.run.ContextRun;
using hxcoro.run.LoopRun;

class CoroRun {
	static var defaultContext(get, null):Context;

	static function get_defaultContext() {
		if (defaultContext != null) {
			return defaultContext;
		}
		final stackTraceManager = new haxe.coro.BaseContinuation.StackTraceManager();
		defaultContext = Context.create(stackTraceManager);
		return defaultContext;
	}

	public static function with(...elements:IElement<Any>):Context {
		return defaultContext.clone().with(...elements);
	}

	overload extern static public inline function run<T>(lambda:Coroutine<() -> T>):T {
		return runWith(defaultContext, _ -> lambda());
	}

	overload extern static public inline function run<T>(lambda:NodeLambda<T>):T {
		return runWith(defaultContext, lambda);
	}

	@:deprecated("Use `CoroRun.run` instead")
	static public function runScoped<T>(lambda:NodeLambda<T>):T {
		return runWith(defaultContext, lambda);
	}

	#if js

	overload extern static public inline function promise<T>(f:Coroutine<() -> T>):js.lib.Promise<T> {
		return promiseImpl(_ -> f());
	}

	overload extern static public inline function promise<T>(lambda:NodeLambda<T>):js.lib.Promise<T> {
		return promiseImpl(lambda);
	}

	static function promiseImpl<T>(lambda:NodeLambda<T>) {
		final scheduler = new HaxeTimerScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task = defaultContext.with(dispatcher).launchTask(lambda);

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
	**/
	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		#if (jvm || cpp || hl)
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final pool = new hxcoro.thread.FixedThreadPool(10);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		function onCompletion() {
			pool.shutDown(true);
		}
		#else
		final scheduler  = new EventLoopScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		function onCompletion() {}
		#end

		final task = scheduler.runTask(context.with(dispatcher), lambda);
		onCompletion();
		return ContextRun.resolveTask(task);
	}
}
