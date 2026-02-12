package hxcoro.run;

import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.schedulers.ILoop;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

/**
	This class provides static extensions for `Context` to work with `Task` instances.

	The intended usage is to add `using hxcoro.run.ContextRun`.
**/
class ContextRun {
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
	static public function createTask<T>(context:Context, lambda:NodeLambda<T>):IStartableCoroTask<T> {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot create a task without a Dispatcher element';
		}
		return new CoroTaskWithLambda(context, lambda, CoroTask.CoroScopeStrategy, Created);
	}

	/**
		Creates a new task using `context` to execute `lambda` and starts it without
		blocking execution.

		This function checks for the presence of a `Dispatcher` element in
		the context and fails if there is none.
	**/
	static public function launchTask<T>(context:Context, lambda:NodeLambda<T>):ICoroTask<T> {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot launch a task without a Dispatcher element';
		}
		return new CoroTaskWithLambda(context, lambda, CoroTask.CoroScopeStrategy);
	}

	/**
		Creates a new task using `context` to execute `lambda` and runs it in a
		blocking manner, then either returns its value or throws its error as an
		exception.

		This function checks for the presence of a `Dispatcher` element in
		the context and fails if there is none. It also checks if the dispatcher's
		scheduler is an instance of `ILoop` and fails if it's not.
	**/
	static public function runTask<T>(context:Context, lambda:NodeLambda<T>):T {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher == null) {
			throw 'Cannot run a task without a Dispatcher element';
		}
		if (!(dispatcher.scheduler is ILoop)) {
			throw 'Cannot run because ${dispatcher.scheduler} is not an instance of ILoop';
		}
		final task = LoopRun.runTask(cast dispatcher.scheduler, context, lambda);
		return resolveTask(task);
	}
}