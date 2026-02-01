package hxcoro;

import haxe.Timer;
import haxe.coro.Coroutine;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;
import hxcoro.task.StartableCoroTask;
import hxcoro.schedulers.EventLoopScheduler;
import hxcoro.schedulers.ILoop;
import hxcoro.schedulers.HaxeTimerScheduler;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.exceptions.TimeoutException;

function resolveTask<T>(task:CoroTask<T>) {
	switch (task.getError()) {
		case null:
			return task.get();
		case error:
			throw error;
	}
}

abstract RunnableContext(ElementTree) {
	inline function new(tree:ElementTree) {
		this = tree;
	}

	public function create<T>(lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new StartableCoroTask(new Context(this), lambda, CoroTask.CoroScopeStrategy);
	}

	public function run<T>(lambda:NodeLambda<T>):T {
		final context = new Context(this);
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot run without a Dispatcher element';
		}
		if (!(dispatcher.scheduler is ILoop)) {
			throw 'Cannot run because ${dispatcher.scheduler} is not an instance of ILoop';
		}
		return resolveTask(CoroRun.runInLoop(context, cast dispatcher.scheduler, lambda));
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
		final stackTraceManager = new haxe.coro.BaseContinuation.StackTraceManager();
		defaultContext = Context.create(stackTraceManager);
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
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task = new CoroTask(defaultContext.clone().with(dispatcher), CoroTask.CoroScopeStrategy);
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

	#else

	/**
		Executes `lambda` in context `context`, blocking until it returns or throws.

		If there exists a `Dispatcher` element in the context, it is ignored. This
		function always installs its own instance of `Dispatcher` into the context
		and uses it to drive execution. The exact dispatcher implementation being
		used depends on the target.

		Refer to `runInLoop` or `with(dispatcher).run()` for using custom execution
		models.
	**/
	static public function runWith<T>(context:Context, lambda:NodeLambda<T>):T {
		#if (jvm || cpp)
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final pool = new hxcoro.thread.FixedThreadPool(10);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		#else
		final scheduler  = new EventLoopScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		#end

		final task = runInLoop(context.clone().with(dispatcher), scheduler, lambda);

		#if (jvm || cpp)
		pool.shutDown(true);
		#end

		return resolveTask(task);
	}

	#end

	/**
		Executes `lambda` in context `context` by running `loop` until a value is
		returned or an exception is thrown.

		It is the responsibility of the user to ensure that the `Dispatcher` element
		in the context and `loop` interact in a manner that leads to termination. For
		example, this function does not verify that the dispatcher's scheduler handles
		events in such a way that the loop processes them.
	**/
	static public function runInLoop<T>(context:Context, loop:ILoop, lambda:NodeLambda<T>):CoroTask<T> {
		final task = new CoroTask(context, CoroTask.CoroScopeStrategy);
		task.runNodeLambda(lambda);

		#if (target.threaded && hxcoro_mt_debug)
		var timeoutTime = Timer.milliseconds() + 10000;
		var cancelLevel = 0;
		#end
		while (task.isActive()) {
			loop.run();
			#if (target.threaded && hxcoro_mt_debug)
			if (Timer.milliseconds() >= timeoutTime) {
				switch (cancelLevel) {
					case 0:
						cancelLevel = 1;
						task.dump();
						task.iterateChildren(child -> {
							if (child.isActive()) {
								Sys.println("Active child: " + child);
								if (child is CoroTask) {
									(cast child : CoroTask<Any>).dump();
								}
							}
						});
						task.cancel(new TimeoutException());
						// Give the task a second to wind down, otherwise break out of here
						timeoutTime += 1000;
					case 1:
						break;
				}
			}
			#end
		}
		return task;
	}
}
