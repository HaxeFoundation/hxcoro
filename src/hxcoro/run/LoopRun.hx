package hxcoro.run;

import haxe.Timer;
import haxe.coro.context.Context;
import hxcoro.schedulers.ILoop;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

/**
	This class provides static extensions for `ILoop` to work with `Task` instances.

	The intended usage is to add `using hxcoro.run.LooptRun`.
**/
class LoopRun {
	/**
		Executes `lambda` in context `context` by running `loop` until a value is
		returned or an exception is thrown.

		It is the responsibility of the user to ensure that the `Dispatcher` element
		in the context and `loop` interact in a manner that leads to termination. For
		example, this function does not verify that the dispatcher's scheduler handles
		events in such a way that the loop processes them.
	**/
	static public function runTask<T>(loop:ILoop, context:Context, lambda:NodeLambda<T>):ICoroTask<T> {
		final task = new CoroTask(context, CoroTask.CoroScopeStrategy);
		task.runNodeLambda(lambda);
		awaitTaskCompletion(loop, task);
		return task;
	}

	/**
		Runs `loop` until `task` is no longer active.

		Execution makes no assumption about the state of the loop itself, it
		only checks for the task's completion.

		This function does not start the task, so it should only be called with tasks
		that are already running.
	**/
	static function awaitTaskCompletion<T>(loop:ILoop, task:ICoroTask<T>) {
		#if (target.threaded && !neko) // need neko nightly
		final semaphore = new sys.thread.Semaphore(0);
		task.onCompletion((_, _) -> {
			loop.wakeUp();
			semaphore.release();
		});
		#end

		while (task.isActive()) {
			loop.loop();
		}

		#if (target.threaded && !neko)
		semaphore.acquire();
		#end
	}

	/**
		Runs `loop` until `task` is no longer active, then returns its value
		or throws its error as an exception.

		Execution makes no assumption about the state of the loop itself, it
		only checks for the task's completion.

		This function also starts the task.
	**/
	static public function awaitTask<T>(loop:ILoop, task:ICoroTask<T>):T {
		if (task is IStartableCoroTask) {
			(cast task : IStartableCoroTask<T>).start();
		}
		awaitTaskCompletion(loop, task);
		return @:privateAccess ContextRun.resolveTask(task);
	}
}