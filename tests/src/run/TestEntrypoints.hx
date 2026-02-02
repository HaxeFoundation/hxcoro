package run;

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

final messages = [];

@:coroutine function helloAndGoodbyeAfter(id:String) {
	messages.push('$id says hello');
	yield();
	messages.push('$id says goodbye');
}

function assertLastMessage(expected:String, ?p:PosInfos) {
	Assert.equals(expected, messages.pop(), p);
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

		loop.loop(Default);

		assertLastMessage("Launched Task 1 says goodbye");
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
		loop.loop(NoWait);

		assertNoCurrentMessage();

		// This will make it say hello but not goodbye because the loop isn't active
		createdTask2.start();

		assertLastMessage("Created Task 2 says hello");

		// But with this we finally get it.
		loop.loop(Once);

		assertLastMessage("Created Task 2 says goodbye");
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

	/**
		Loop termination doesn't react to threads it doesn't know yet, so this needs a
		different approach. I think the ThreadPool has to become aware of the loop,
		otherwise this is always going to cause problems.
	**/
	// #if target.threaded

	// public function testThreadPool() {
	// 	final scheduler = new ThreadAwareScheduler();
	// 	final pool = new FixedThreadPool(1);
	// 	final dispatcher = new ThreadPoolDispatcher(scheduler, pool);
	// 	final context = CoroRun.with(dispatcher);
	// 	runSuite(context, scheduler);
	// 	pool.shutDown();
	// }

	// #end
}