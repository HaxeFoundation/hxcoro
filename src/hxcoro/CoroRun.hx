package hxcoro;

import haxe.Timer;
import haxe.coro.Coroutine;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import hxcoro.schedulers.HaxeTimerScheduler;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;
import hxcoro.task.StartableCoroTask;
import hxcoro.schedulers.EventLoopScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.exceptions.TimeoutException;

abstract RunnableContext(ElementTree) {
	inline function new(tree:ElementTree) {
		this = tree;
	}

	public function create<T>(lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new StartableCoroTask(new Context(this), lambda, CoroTask.CoroScopeStrategy);
	}

	public function run<T>(lambda:NodeLambda<T>):T {
		return CoroRun.runWith(new Context(this), lambda);
	}

	@:from static function fromAdjustableContext(context:AdjustableContext) {
		return new RunnableContext(cast context);
	}

	public function with(...elements:IElement<Any>):RunnableContext {
		return new AdjustableContext(this.copy()).with(...elements);
	}
}

class CoroRun {
	static var defaultContext(get, null):Context;

	static function get_defaultContext() {
		if (defaultContext != null) {
			return defaultContext;
		}
		final stackTraceManagerComponent = new haxe.coro.BaseContinuation.StackTraceManager();
		defaultContext = Context.create(stackTraceManagerComponent);
		return defaultContext;
	}

	public static function with(...elements:IElement<Any>):RunnableContext {
		return defaultContext.clone().with(...elements);
	}

	static public function run<T>(lambda:Coroutine<() -> T>):T {
		return runScoped(_ -> lambda());
	}

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
		final dispatcherComponent = new TrampolineDispatcher(scheduler);
		final task = new CoroTask(defaultContext.clone().with(dispatcherComponent), CoroTask.CoroScopeStrategy);
		task.runNodeLambda(lambda);

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

	#if (false && (eval && !macro))

	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		final loop = eval.luv.Loop.init().resolve();
		final pool = new hxcoro.thread.FixedThreadPool(1);
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);

		final scope = new CoroTask(context.clone().with(dispatcher), CoroTask.CoroScopeStrategy);
		scope.onCompletion((_, _) -> scheduler.shutdown());
		scope.runNodeLambda(lambda);

		while (loop.run(NOWAIT)) { }

		pool.shutdown();
		loop.close();

		switch (scope.getError()) {
			case null:
				return scope.get();
			case error:
				throw error;
		}
	}

	#elseif (cpp && hxcpp_luv_io)

	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		final loop = cpp.luv.Luv.allocLoop();
		final dispatcher = new hxcoro.schedulers.LuvScheduler.LuvDispatcher(loop);

		final scope = new CoroTask(context.clone().with(dispatcher), CoroTask.CoroScopeStrategy);
		scope.onCompletion((_, _) -> {
			dispatcher.shutdown();
		});
		scope.runNodeLambda(lambda);

		cpp.luv.Luv.runLoop(loop, Default);
		cpp.luv.Luv.freeLoop(loop);
		// dispatcher.shutdown();

		switch (scope.getError()) {
			case null:
				return scope.get();
			case error:
				throw error;
		}
	}

	#elseif (jvm || cpp)

	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final pool = new hxcoro.thread.FixedThreadPool(10);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		final scope = new CoroTask(context.clone().with(dispatcher), CoroTask.CoroScopeStrategy);
		scope.runNodeLambda(lambda);

		#if hxcoro_mt_debug
		var timeoutTime = Timer.milliseconds() + 10000;
		var cancelLevel = 0;
		#end
		while (scope.isActive()) {
			scheduler.run();
			pool.ping();
			#if hxcoro_mt_debug
			if (Timer.milliseconds() >= timeoutTime) {
				switch (cancelLevel) {
					case 0:
						cancelLevel = 1;
						scope.dump();
						scope.iterateChildren(child -> {
							if (child.isActive()) {
								Sys.println("Active child: " + child);
								if (child is CoroTask) {
									(cast child : CoroTask<Any>).dump();
								}
							}
						});
						pool.dump();
						scheduler.dump();
						scope.cancel(new TimeoutException());
						// Give the task a second to wind down, otherwise break out of here
						timeoutTime += 1000;
					case 1:
						break;
				}
			}
			#end
		}

		pool.shutdown(true);

		switch (scope.getError()) {
			case null:
				return scope.get();
			case error:
				throw error;
		}
	}

	#else

	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		final schedulerComponent  = new EventLoopScheduler();
		final dispatcherComponent = new TrampolineDispatcher(schedulerComponent);
		final scope = new CoroTask(context.clone().with(dispatcherComponent), CoroTask.CoroScopeStrategy);
		scope.runNodeLambda(lambda);

		while (scope.isActive()) {
			schedulerComponent.run();
		}

		switch (scope.getError()) {
			case null:
				return scope.get();
			case error:
				throw error;
		}
	}

	#end
}
