package hxcoro.task;

import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.Coro;
import hxcoro.task.CoroBaseTask;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;
import hxcoro.task.TaskKind;

/**
	Static extensions for `Context` that create tasks as children of the task in the context.

	A `NodeContext`, as returned by a node, offers them without a `using` directive. For any other
	`Context`, add `using hxcoro.task.ContextTasks`.
**/
class ContextTasks {
	/**
		Starts executing `lambda` in a new child task of the task in `context`.

		Throws `CoroutineException` if `context` contains no task, and `InvalidTaskStateException` if
		that task has already completed.
	**/
	static public function async<T>(context:Context, lambda:NodeLambda<T>):ICoroTask<T> {
		// A task without a parent would be held by nobody, so its failure would go unnoticed. Tasks
		// without a parent are created through `hxcoro.run.ContextRun`, which hands them to the caller.
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
