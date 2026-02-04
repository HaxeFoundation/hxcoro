package hxcoro.run;

import haxe.coro.dispatchers.Dispatcher;
import hxcoro.schedulers.ILoop;

class Setup {
	public final loop:ILoop;
	public final dispatcher:Dispatcher;
	public final onCompletion:() -> Void;

	public function new(loop:ILoop, dispatcher:Dispatcher, onCompletion:() -> Void) {
		this.loop = loop;
		this.dispatcher = dispatcher;
		this.onCompletion = onCompletion;
	}

	static public function createEventLoopTrampoline() {
		final scheduler = new hxcoro.schedulers.EventLoopScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		function onCompletion() {}
		return new Setup(scheduler, dispatcher, onCompletion);
	}

	static public function createVirtualTrampoline() {
		final scheduler = new hxcoro.schedulers.VirtualTimeScheduler();
		final dispatcher = new hxcoro.dispatchers.TrampolineDispatcher(scheduler);
		function onCompletion() {}
		return new Setup(scheduler, dispatcher, onCompletion);
	}

	#if (cpp && hxcpp_luv_io)

	static public function createLuv() {
		final loop = cpp.luv.Luv.allocLoop();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = new hxcoro.dispatchers.LuvDispatcher(loop, scheduler);
		function onCompletion() {
			dispatcher.shutDown();
			cpp.luv.Luv.stopLoop(loop);
			cpp.luv.Luv.shutdownLoop(loop);
			cpp.luv.Luv.freeLoop(loop);
		}
		return new Setup(scheduler, dispatcher, onCompletion);
	}

	#end

	static public function createThreadPool(numThreads:Int) {
		final scheduler = new hxcoro.schedulers.ThreadAwareScheduler();
		final pool = new hxcoro.thread.FixedThreadPool(numThreads);
		final dispatcher = new hxcoro.dispatchers.ThreadPoolDispatcher(scheduler, pool);
		function onCompletion() {
			pool.shutDown(true);
		}
		return new Setup(scheduler, dispatcher, onCompletion);
	}

	static public function createDefault() {
		#if (cpp && hxcpp_luv_io)
		return createLuv();
		#elseif (jvm || cpp || hl)
		return createThreadPool(10);
		#else
		return createEventLoopTrampoline();
		#end
	}
}