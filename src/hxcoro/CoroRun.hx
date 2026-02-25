package hxcoro;

import haxe.coro.Mutex;
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

	static var setup:Null<LoopSetup>;
	static final setupMutex = new Mutex();

	/**
		Executes `lambda` in context `context`, blocking until it returns or throws.

		If there exists a `Dispatcher` element in the context, it is ignored. This
		function always installs its own instance of `Dispatcher` into the context
		and uses it to drive execution. The exact dispatcher implementation being
		used depends on the target.
	**/
	static public function runWith<T>(context:Context, lambda:NodeLambda<T>#if debug, ?callPos:haxe.PosInfos#end):T {
		#if target.threaded
		setupMutex.acquire();
		final setup = if (setup == null) {
			final setup = Setup.createDefault();
			sys.thread.Thread.current().onExit(() -> setup.close());
			setup;
		} else {
			setup;
		}
		setupMutex.release();
		#else
		final setup = Setup.createDefault();
		#end
		final context = setup.adaptContext(context);
		final task = setup.loop.runTask(context, lambda#if debug, callPos#end);
		#if !target.threaded
		setup.close();
		#end
		return @:privateAccess ContextRun.resolveTask(task);
	}
}