package hxcoro.run;

import haxe.coro.context.Context;
import haxe.coro.context.CallStackHandler;
import haxe.coro.dispatchers.Dispatcher;
import haxe.exceptions.CoroutineException;
import hxcoro.schedulers.ILoop;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;
import hxcoro.task.TaskKind;

/**
	This class provides static extensions for `Context` to work with `Task` instances.

	The intended usage is to add `using hxcoro.run.ContextRun`.
**/
class ContextRun {
	#if coro.stack_traces

	static function createEntryTask<T>(context:Context, lambda:NodeLambda<T>, start:Bool, ?callPos:haxe.PosInfos) {
		final callStackHandler = context.get(CallStackHandler);
		final task = if (callStackHandler != null) {
			@:nullSafety(Off) final run = callStackHandler.startSynchronousRun(context, callPos);
			final task = new CoroTaskWithLambda(run.context, lambda, Sequential, callPos);
			task.onCompletion((_, _) -> run.complete());
			task;
		} else {
			new CoroTaskWithLambda(context, lambda, Sequential, callPos);
		}
		if (start) {
			task.requestActivation();
		}
		return task;
	}

	#else

	static function createEntryTask<T>(context:Context, lambda:NodeLambda<T>, start:Bool) {
		final task = new CoroTaskWithLambda(context, lambda, Sequential);
		if (start) {
			task.requestActivation();
		}
		return task;
	}

	#end

	/**
		Resolves `task` by either returning its value or throwing
		its error as an exception. This function does not check the
		actual state of the task and should only be called on tasks
		that are known to no longer be active.
	**/
	static function resolveTask<T>(task:ICoroTask<T>) {
		switch (task.getError()) {
			case null:
				return task.get();
			case error:
				throw error;
		}
	}

	/**
		Creates a new task using `context` to execute `lambda`. Does not
		start the task.

		Throws `CoroutineException` if `context` has no `Dispatcher` element.
	**/
	static public function createTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):IStartableCoroTask<T> {
		context.getOrRaise(Dispatcher);
		return createEntryTask(context, lambda, false#if coro.stack_traces, callPos#end);
	}

	/**
		Creates a new task using `context` to execute `lambda` and starts it without
		blocking execution.

		Throws `CoroutineException` if `context` has no `Dispatcher` element.
	**/
	static public function launchTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):ICoroTask<T> {
		context.getOrRaise(Dispatcher);
		return createEntryTask(context, lambda, true#if coro.stack_traces, callPos #end);
	}

	/**
		Creates a new task using `context` to execute `lambda` and runs it in a
		blocking manner, then either returns its value or throws its error as an
		exception.

		Throws `CoroutineException` if `context` has no `Dispatcher` element, or if the
		dispatcher's scheduler is not an `ILoop`.
	**/
	static public function runTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):T {
		final dispatcher = context.getOrRaise(Dispatcher);
		if (!(dispatcher.scheduler is ILoop)) {
			throw new CoroutineException('Cannot run a task because ${dispatcher.scheduler} is not an ILoop');
		}
		final task = LoopRun.runTask(cast dispatcher.scheduler, context, lambda#if coro.stack_traces, callPos #end);
		return resolveTask(task);
	}
}