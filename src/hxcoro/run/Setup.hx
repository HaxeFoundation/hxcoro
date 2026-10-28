package hxcoro.run;

import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.schedulers.IScheduler;
import hxcoro.elements.DefaultExceptionHandler;
import hxcoro.schedulers.ILoop;

/**
	Combines a `Dispatcher` with the code needed to shut it down, and provides factory
	functions for the dispatcher configurations supported by hxcoro.
**/
class Setup {
	/**
		The base context used by `CoroRun`, which contains a `DefaultExceptionHandler`.
	**/
	static public final defaultContext = Context.empty.with(new DefaultExceptionHandler());

	/**
		The `Dispatcher` that this setup installs into contexts.
	**/
	public final dispatcher:Dispatcher;
	final finalize:Null<() -> Void>;

	public function new(dispatcher:Dispatcher, ?finalize:() -> Void) {
		this.dispatcher = dispatcher;
		this.finalize = finalize;
	}

	/**
		Returns a new context containing this setup's `Dispatcher` instance as an
		element, and the default context's `ExceptionHandler` if no such element
		exists in `context`.
	**/
	public function adaptContext(context:Context) {
		return (defaultContext + context).with(dispatcher);
	}

	/**
		Returns a new context containing this setup's `Dispatcher` instance as an
		element, and the default context's `ExceptionHandler`.
	**/
	public function createContext() {
		return defaultContext.with(dispatcher);
	}

	/**
		Closes this setup, running the finalization code. Does not affect this setup's
		`dispatcher` directly.
	**/
	public function close() {
		if (finalize != null) {
			finalize();
		}
	}

	/**
		Creates a single-threaded setup that uses a `TrampolineDispatcher` with a
		`RealTimeScheduler`.
	**/
	static public function createTrampoline() {
		final scheduler = new hxcoro.schedulers.RealTimeScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		return new LoopSetup(scheduler, dispatcher);
	}

	/**
		Creates a single-threaded setup that uses a `TrampolineDispatcher` with a
		`VirtualTimeScheduler`, which simulates time instead of reading a clock.
	**/
	static public function createVirtualTrampoline() {
		final scheduler = new hxcoro.schedulers.VirtualTimeScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		return new LoopSetup(scheduler, dispatcher);
	}

	#if (cpp && hxcpp_luv_io)

	/**
		Creates a setup with a `LuvScheduler` on a newly allocated libuv loop. The dispatcher is
		created by `createDispatcher` and shut down by `shutDownDispatcher` when the setup is closed.
	**/
	static public function createLuvGen<T:Dispatcher>(createDispatcher:(cpp.luv.Luv.LuvLoop, IScheduler) -> T, shutDownDispatcher:T -> Void) {
		final loop = cpp.luv.Luv.allocLoop();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = createDispatcher(loop, scheduler);
		function finalize() {
			scheduler.shutDown();
			shutDownDispatcher(dispatcher);
			cpp.luv.Luv.stopLoop(loop);
			cpp.luv.Luv.freeLoop(loop);
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	/**
		Creates a setup that uses a `LuvDispatcher` and `LuvScheduler` on a new libuv loop.
	**/
	static public function createLuv() {
		return createLuvGen(
			(uvLoop, loop) -> new hxcoro.dispatchers.LuvDispatcher(uvLoop, loop),
			dispatcher -> dispatcher.shutDown()
		);
	}

	/**
		Creates a setup with a `LuvScheduler` on a new libuv loop and a `ThreadPoolDispatcher`
		that runs work on a pool of 10 threads.
	**/
	static public function createLuvThreadPool() {
		final pool = new hxcoro.thread.FixedThreadPool(10);
		return createLuvGen(
			(uvLoop, loop) -> new hxcoro.dispatchers.ThreadPoolDispatcher(loop, pool),
			dispatcher -> pool.shutDown()
		);
	}

	#elseif interp

	/**
		Creates a setup that uses a `LuvDispatcher` and `LuvScheduler` on a new libuv loop.
	**/
	static public function createLuv() {
		final loop = eval.luv.Loop.init().resolve();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = new hxcoro.dispatchers.LuvDispatcher(loop, scheduler);
		function finalize() {
			scheduler.shutdown();
			loop.stop();
			loop.close();
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	#end

	#if target.threaded

	/**
		Creates a setup with a `ThreadPoolDispatcher` that runs work on a pool of `numThreads`
		threads. Closing the setup shuts down the pool and blocks until its threads have exited.
	**/
	static public function createThreadPool(numThreads:Int) {
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final pool = new hxcoro.thread.FixedThreadPool(numThreads);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		function finalize() {
			pool.shutDown(true);
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	#end

	/**
		Creates the default setup for the current target, as used by `CoroRun.runWith`: a
		thread pool of 10 threads on JVM, C++ and eval (combined with libuv on C++ with
		`hxcpp_luv_io`), and `createTrampoline` otherwise.
	**/
	static public function createDefault() {
		#if (cpp && hxcpp_luv_io)
		return createLuvThreadPool();
		#elseif (jvm || cpp || interp)
		return createThreadPool(10);
		#else
		return createTrampoline();
		#end
	}
}

/**
	A `Setup` whose scheduler is an `ILoop` that has to be driven explicitly, e.g. via
	`hxcoro.run.LoopRun`.
**/
class LoopSetup extends Setup {
	/**
		The loop that has to be run in order for this setup's dispatcher to make progress.
	**/
	public final loop:ILoop;

	public function new(loop:ILoop, dispatcher:Dispatcher, ?finalize:() -> Void) {
		super(dispatcher, finalize);
		this.loop = loop;
	}
}