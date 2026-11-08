package hxcoro.run;

import haxe.coro.context.Context;
import haxe.coro.context.CallStackHandler;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.Coro;
import hxcoro.schedulers.ILoop;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;
import hxcoro.task.TaskKind;

/**
	This class provides static extensions for `Context` to create and run tasks: root tasks that
	are handed to the caller, and child tasks of the task in the context.

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

		This function checks for the presence of a `Dispatcher` element in
		the context and fails if there is none.
	**/
	static public function createTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):IStartableCoroTask<T> {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot create a task without a Dispatcher element';
		}
		return createEntryTask(context, lambda, false);
	}

	/**
		Creates a new task using `context` to execute `lambda` and starts it without
		blocking execution.

		This function checks for the presence of a `Dispatcher` element in
		the context and fails if there is none.
	**/
	static public function launchTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):ICoroTask<T> {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot launch a task without a Dispatcher element';
		}
		return createEntryTask(context, lambda, true#if coro.stack_traces, callPos #end);
	}

	/**
		Creates a new task using `context` to execute `lambda` and runs it in a
		blocking manner, then either returns its value or throws its error as an
		exception.

		This function checks for the presence of a `Dispatcher` element in
		the context and fails if there is none. It also checks if the dispatcher's
		scheduler is an instance of `ILoop` and fails if it's not.
	**/
	static public function runTask<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):T {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot run a task without a Dispatcher element';
		}
		if (!(dispatcher.scheduler is ILoop)) {
			throw 'Cannot run because ${dispatcher.scheduler} is not an instance of ILoop';
		}
		final task = LoopRun.runTask(cast dispatcher.scheduler, context, lambda#if coro.stack_traces, callPos #end);
		return resolveTask(task);
	}

	/**
		Starts executing `lambda` in a new child task of the task in `context`.

		Throws `CoroutineException` if `context` contains no task, and `InvalidTaskStateException` if
		that task has already completed.
	**/
	static public function async<T>(context:Context, lambda:NodeLambda<T>):ICoroTask<T> {
		// A task without a parent would be held by nobody, so its failure would go unnoticed. Tasks
		// without a parent are created through `createTask` and `launchTask`, which hand them to the caller.
		context.getOrRaise(CoroBaseTask);
		final task = new CoroTaskWithLambda<T>(context, lambda, Concurrent);
		task.requestActivation();
		return task;
	}

	/**
		Like `async`, but the task does not run `lambda` until it is started, which happens
		automatically once the parent task has finished its own work, or right away if it already has.
	**/
	static public function lazy<T>(context:Context, lambda:NodeLambda<T>):IStartableCoroTask<T> {
		final parent = context.getOrRaise(CoroBaseTask);
		final task = new CoroTaskWithLambda(context, lambda, Concurrent);
		parent.startLateLazyChild(task);
		return task;
	}

	/**
		Executes `lambda` in a new `Sequential` task created with `context` and returns its result once
		the task and all its children have completed, like `Coro.scope`. If `context` contains a task,
		the new task becomes its child; otherwise the new task has no parent: the caller still waits
		for it, but cancelling the caller does not cancel it.

		If `lambda` or one of the children raises an exception, the remaining children are cancelled
		and the exception is thrown from this call. The caller waits for the block even if it is
		cancelled in the meantime.

		The block runs on the `Dispatcher` of `context`. If that is the caller's own dispatcher, the
		block starts synchronously, before this call suspends; otherwise it is dispatched there. In
		both cases the caller resumes on its own dispatcher once the block has completed.
	**/
	@:coroutine static public function scope<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):T {
		return Coro.suspend(cont -> {
			final scope = new CoroTaskWithLambda(context, lambda, Sequential#if coro.stack_traces, startPos#end);
			if (context.get(Dispatcher) == cont.context.get(Dispatcher)) {
				// We already run on the scope's dispatcher, so activate it ourselves.
				scope.onDispatch();
			}
			// Otherwise this starts the scope, which dispatches it.
			scope.awaitContinuation(cont#if coro.stack_traces, startPos#end);
		});
	}
}
