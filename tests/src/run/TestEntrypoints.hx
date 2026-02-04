package run;

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
		final scheduler = new EventLoopScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final context = CoroRun.with(dispatcher);
		runSuite(context, scheduler);
	}

	public function testVirtualTrampoline() {
		final scheduler = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final context = CoroRun.with(dispatcher);
		runSuite(context, scheduler);
	}

	// Need neko nightly for condition variables
	// Python hates this for some other reason that needs investigation
	#if (target.threaded && !neko && !python)

	public function testThreadPool() {
		final scheduler = new ThreadAwareScheduler();
		final pool = new FixedThreadPool(1);
		final dispatcher = new ThreadPoolDispatcher(scheduler, pool);
		final context = CoroRun.with(dispatcher);
		runSuite(context, scheduler);
		pool.shutDown();
		scheduler.loop();
	}

	#end
}