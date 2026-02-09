package hxcoro.run;

import haxe.coro.BaseContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.schedulers.ILoop;

class Setup {
	static public final defaultContext = Context.empty.with(new StackTraceManager());

	public final dispatcher:Dispatcher;
	final finalize:Null<() -> Void>;

	public function new(dispatcher:Dispatcher, ?finalize:() -> Void) {
		this.dispatcher = dispatcher;
		this.finalize = finalize;
	}

	/**
		Returns a new context containing this setup's `Dispatcher` instance as an
		element, and the default context's `StackTraceManager` if no such element
		exists in `context`.
	**/
	public function adaptContext(context:Context) {
		return (defaultContext + context).with(dispatcher);
	}

	/**
		Returns a new context containing this setup's `Dispatcher` instance as an
		element, and the default context's `StackTraceManager`.
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

	static public function createEventLoopTrampoline() {
		final scheduler = new hxcoro.schedulers.EventLoopScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		return new LoopSetup(scheduler, dispatcher);
	}

	static public function createVirtualTrampoline() {
		final scheduler = new hxcoro.schedulers.VirtualTimeScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		return new LoopSetup(scheduler, dispatcher);
	}

	#if (cpp && hxcpp_luv_io)

	static public function createLuv() {
		final loop = cpp.luv.Luv.allocLoop();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		// final dispatcher = new hxcoro.dispatchers.LuvDispatcher(loop, scheduler);
		final pool = new hxcoro.thread.FixedThreadPool(10);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		function finalize() {
			// dispatcher.shutDown();
			scheduler.shutDown();
			pool.shutDown();
			cpp.luv.Luv.stopLoop(loop);
			cpp.luv.Luv.shutdownLoop(loop);
			cpp.luv.Luv.freeLoop(loop);
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	#elseif interp

	static public function createLuv() {
		final loop = eval.luv.Loop.init().resolve();
		final pool = new hxcoro.thread.FixedThreadPool(1);
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		function finalize() {
			scheduler.shutdown();
			pool.shutDown();
			loop.stop();
			loop.close();
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	#end

	#if target.threaded

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

	static public function createDefault() {
		#if (cpp && hxcpp_luv_io || interp)
		return createLuv();
		#elseif (jvm || cpp || hl)
		return createThreadPool(10);
		#else
		return createEventLoopTrampoline();
		#end
	}
}

class LoopSetup extends Setup {
	public final loop:ILoop;

	public function new(loop:ILoop, dispatcher:Dispatcher, ?finalize:() -> Void) {
		super(dispatcher, finalize);
		this.loop = loop;
	}
}