package hxcoro.task;

import hxcoro.concurrent.AtomicState;
import hxcoro.task.node.CoroChildStrategy;
import hxcoro.task.node.CoroScopeStrategy;
import hxcoro.task.node.CoroSupervisorStrategy;
import hxcoro.task.node.INodeStrategy;
import hxcoro.task.AbstractTask;
import haxe.coro.IContinuation;
import haxe.coro.context.Key;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.Exception;

private enum abstract ResumeStatus(Int) to Int {
	final NeverStarted;
	final Unresumed;
	final Resumed;
}

class CoroTask<T> extends CoroBaseTask<T> implements IContinuation<T> {
	public static final key = new Key<CoroBaseTask<Any>>('Task');

	static public final CoroChildStrategy = new CoroChildStrategy();
	static public final CoroScopeStrategy = new CoroScopeStrategy();
	static public final CoroSupervisorStrategy = new CoroSupervisorStrategy();

	var resumeStatus:AtomicState<ResumeStatus>;

	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState = Running) {
		resumeStatus = new AtomicState(NeverStarted);
		super(context, nodeStrategy, initialState);
	}

	function updateResumeStatus(expected:ResumeStatus, replacement:ResumeStatus, where:String) {
		final previousStatus = resumeStatus.compareExchange(expected, replacement);
		if (previousStatus != expected) {
			setInternalException('Unexpected resume status $previousStatus in $where, task state ${state.load()}');
		}
	}

	public function doStart() {
		updateResumeStatus(NeverStarted, Unresumed, "doStart");
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
		updateResumeStatus(Unresumed, Resumed, "resume");
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
		return resumeStatus.load() == Unresumed;
	}

	#if sys
	public function dump() {
		Sys.println('CoroTask $id');
		Sys.println('\tstate: ${state.load()}');
		Sys.println('\tfirstChild: $firstChild');
		Sys.println('\tnumActiveChildren: ${numActiveChildren.load()}');
		Sys.println('\tresumeStatus: ${resumeStatus.load()}');
		Sys.println('\tresult: $result');
		Sys.println('\terror: $error');
	}
	#end
}

class CoroTaskWithLambda<T> extends CoroTask<T> implements IDispatchObject {
	final lambda:NodeLambda<T>;

	/**
		Creates a new task using the provided `context` in order to execute `lambda`.
	**/
	public function new(context:Context, lambda:NodeLambda<T>, nodeStrategy:INodeStrategy) {
		super(context, nodeStrategy);
		this.lambda = lambda;
	}

	public function onDispatch() {
		runNodeLambda(lambda);
	}
}