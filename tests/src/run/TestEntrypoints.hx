package run;

import haxe.coro.schedulers.IScheduler;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.run.Setup;
import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.VirtualTimeScheduler;
#if target.threaded
import hxcoro.schedulers.ThreadAwareScheduler;
import hxcoro.thread.FixedThreadPool;
import hxcoro.dispatchers.ThreadPoolDispatcher;
#end
import haxe.coro.Mutex;
import hxcoro.schedulers.EventLoopScheduler;
import haxe.PosInfos;
import hxcoro.schedulers.ILoop;
import haxe.coro.context.Context;
import hxcoro.dispatchers.TrampolineDispatcher;

// This is silly, should just have a thread-safe stack.
final mutex = new Mutex();
final messages = [];

function push(message:String) {
	mutex.acquire();
	messages.push(message);
	mutex.release();
}

@:coroutine function helloAndGoodbyeAfter(id:String) {
	push('$id says hello');
	yield();
	push('$id says goodbye');
}

function assertLastMessage(expected:String, ?p:PosInfos) {
	Assert.equals(expected, messages.pop(), p);
}

function assertAwaitLastMessage(expected:String, ?p:PosInfos) {
	while (true) {
		if (!mutex.tryAcquire()) {
			continue;
		}
		final message = messages.pop();
		if (message != null) {
			Assert.equals(expected, message, p);
			mutex.release();
			return;
		}
		mutex.release();
	}
}

function assertNoCurrentMessage(?p:PosInfos) {
	if (messages.length > 0) {
		Assert.fail('Unexpected message: ${messages.pop()}', p);
	}
}

class TestEntrypoints extends utest.Test {
	function launchTask(context:Context, loop:ILoop) {
		context.launchTask(node -> {
			helloAndGoodbyeAfter("Launched Task 1");
		});

		assertLastMessage("Launched Task 1 says hello");
		assertNoCurrentMessage();

		loop.loop();

		assertAwaitLastMessage("Launched Task 1 says goodbye");
		assertNoCurrentMessage();
	}

	function createTasks(context:Context, loop:ILoop) {
		final createdTask1 = context.createTask(node -> {
			helloAndGoodbyeAfter("Created Task 1");
			return "Created Task 1 return value";
		});

		final createdTask2 = context.createTask(node -> {
			helloAndGoodbyeAfter("Created Task 2");
		});

		assertNoCurrentMessage();

		// Waits for the first task to finish. This also starts it.
		Assert.equals("Created Task 1 return value", loop.awaitTask(createdTask1));

		assertLastMessage("Created Task 1 says goodbye");
		assertLastMessage("Created Task 1 says hello");
		assertNoCurrentMessage();

		// Created Task 2 is still missing, but it was never started so running the loop at this point doesn't do anything.
		loop.loop();

		assertNoCurrentMessage();

		// This will make it say hello but not goodbye because the loop isn't active
		createdTask2.start();

		assertLastMessage("Created Task 2 says hello");

		// But with this we finally get it.
		loop.loop();

		assertAwaitLastMessage("Created Task 2 says goodbye");
		assertNoCurrentMessage();
	}

	function runSuite(context:Context, loop:ILoop) {
		launchTask(context, loop);
		createTasks(context, loop);
	}

	public function testEventTrampoline() {
		final setup = Setup.createEventLoopTrampoline();
		final context = setup.createContext();
		runSuite(context, setup.loop);
	}

	public function testVirtualTrampoline() {
		final setup = Setup.createVirtualTrampoline();
		final context = setup.createContext();
		runSuite(context, setup.loop);
	}

	// Python hates this for some other reason that needs investigation
	#if (target.threaded && !python)

	public function testThreadPool() {
		final setup = Setup.createThreadPool(10);
		final context = setup.createContext();
		runSuite(context, setup.loop);
		setup.close();
	}

	#end

	#if (cpp && hxcpp_luv_io)

	function setupLuv(createDispatcher:(cpp.luv.Luv.LuvLoop, IScheduler) -> Dispatcher) {
		final loop = cpp.luv.Luv.allocLoop();
		final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
		final dispatcher = createDispatcher(loop, scheduler);
		function finalize() {
			scheduler.shutDown();
			cpp.luv.Luv.stopLoop(loop);
			cpp.luv.Luv.shutdownLoop(loop);
			cpp.luv.Luv.freeLoop(loop);
		}
		return new LoopSetup(scheduler, dispatcher, finalize);
	}

	public function testLuvTrampoline() {
		final setup = setupLuv((uvLoop, loop) -> new TrampolineDispatcher(loop));
		final context = setup.createContext();
		runSuite(context, setup.loop);
		setup.close();
	}


	public function testLuvThreadPool() {
		final pool = new hxcoro.thread.FixedThreadPool(1);
		final setup = setupLuv((uvLoop, loop) -> new ThreadPoolDispatcher(loop, pool));
		final context = setup.createContext();
		runSuite(context, setup.loop);
		setup.close();
		pool.shutDown();
	}

	// public function testLuvLuv() {
	// 	final loop = cpp.luv.Luv.allocLoop();
	// 	final scheduler = new hxcoro.schedulers.LuvScheduler(loop);
	// 	final dispatcher = new hxcoro.dispatchers.LuvDispatcher(loop, scheduler);
	// 	final context = CoroRun.with(dispatcher);
	// 	runSuite(context, scheduler);
	// 	dispatcher.shutDown();
	// 	scheduler.shutDown();
	// 	cpp.luv.Luv.stopLoop(loop);
	// 	cpp.luv.Luv.shutdownLoop(loop);
	// 	cpp.luv.Luv.freeLoop(loop);
	// }

	#end
}