package hxcoro.task;

import hxcoro.task.node.CoroChildStrategy;
import hxcoro.task.node.CoroScopeStrategy;
import hxcoro.task.node.CoroSupervisorStrategy;
import hxcoro.task.node.INodeStrategy;
import hxcoro.task.AbstractTask;
import haxe.coro.IContinuation;
import haxe.coro.context.Key;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.IScheduleObject;
import haxe.Exception;

class CoroTask<T> extends CoroBaseTask<T> implements IContinuation<T> {
	public static final key = new Key<CoroBaseTask<Any>>('Task');

	static public final CoroChildStrategy = new CoroChildStrategy();
	static public final CoroScopeStrategy = new CoroScopeStrategy();
	static public final CoroSupervisorStrategy = new CoroSupervisorStrategy();

	var wasResumed:Bool;

	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState = Running) {
		// If we never start we can consider the task resumed for checkCompletion
		if (initialState == Created) {
			wasResumed = true;
		}
		super(context, nodeStrategy, initialState);
	}

	public function doStart() {
		wasResumed = false;
	}

	public function runNodeLambda(lambda:NodeLambda<T>) {
		start();
		final result = lambda(this, this);
		switch result.state {
			case Pending:
				return;
			case Returned:
				this.succeedSync(result.result);
			case Thrown:
				this.failSync(result.error);
		}
	}

	/**
		Resumes the task with the provided `result` and `error`.
	**/
	public function resume(result:T, error:Exception) {
		wasResumed = true;
		if (error == null) {
			switch (state.load()) {
				case Running:
					beginCompleting(() -> {
						this.result = result;
					});
				case _:
			}
			checkCompletion();
		} else {
			this.error ??= error;
			cancel();
		}
	}

	function isDoingSomething() {
		return !wasResumed;
	}
}

class CoroTaskWithLambda<T> extends CoroTask<T> implements IScheduleObject {
	final lambda:NodeLambda<T>;

	/**
		Creates a new task using the provided `context` in order to execute `lambda`.
	**/
	public function new(context:Context, lambda:NodeLambda<T>, nodeStrategy:INodeStrategy) {
		super(context, nodeStrategy);
		this.lambda = lambda;
	}

	public function onSchedule() {
		runNodeLambda(lambda);
	}
}