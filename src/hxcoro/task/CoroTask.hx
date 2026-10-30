package hxcoro.task;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.task.AbstractTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.node.CoroChildStrategy;
import hxcoro.task.node.CoroScopeStrategy;
import hxcoro.task.node.CoroSupervisorStrategy;
import hxcoro.task.node.INodeStrategy;

@:using(CoroTask.ResumeStatusTools)
private enum abstract ResumeStatus(Int) to Int {
	final NeverStarted;
	final Unresumed;
	final Resumed;
}

private class ResumeStatusTools {
	static public function toString(status:ResumeStatus) {
		return switch (status) {
			case NeverStarted: "NeverStarted";
			case Unresumed: "Unresumed";
			case Resumed: "Resumed";
		}
	}
}

/**
	A task that is completed by resuming it as an `IContinuation` with its result or error.
**/
class CoroTask<T> extends CoroBaseTask<T> implements IContinuation<T> {
	static public final CoroChildStrategy = new CoroChildStrategy();
	static public final CoroScopeStrategy = new CoroScopeStrategy();
	static public final CoroSupervisorStrategy = new CoroSupervisorStrategy();

	/**
		Creates a new task using the provided `context`. The creator of the task does its work and
		completes it by calling `resume`, after starting it with `start`.
	**/
	public function new(context:Context, nodeStrategy:INodeStrategy#if coro.stack_traces, ?startPos:haxe.PosInfos#end) {
		super(context, nodeStrategy#if coro.stack_traces, startPos#end);
	}

	/**
		The creator of this task does its work, so there is nothing to dispatch and the task starts
		right away.
	**/
	function dispatchStart() {
		#if coro.stack_traces
		callFrameLocked = true;
		#end
		activate();
	}

	/**
		Resumes the task with the provided `result` and `error`.
	**/
	public function resume(result:T, error:Exception) {
		if (error == null) {
			if (ownWorkSucceeds()) {
				this.result = result;
				startChildren();
			}
		} else {
			ownWorkFails(error);
		}
		checkCompletion();
	}

	#if sys
	/**
		Prints the task's internal state to standard output, for debugging.
	**/
	public function dump() {
		Sys.println('CoroTask $id');
		Sys.println('\tstate: ${state.load().toString()}');
		Sys.println('\tfirstChild: ${firstChild}');
		Sys.println('\tnumActiveChildren: ${numActiveChildren.load()}');
		Sys.println('\tresult: $result');
		Sys.println('\terror: ${error.load()}');
	}
	#end
}

/**
	A task that executes a `NodeLambda`, as created by `async`, `lazy` and functions such as `Coro.scope`.
**/
class CoroTaskWithLambda<T> extends CoroTask<T> implements IDispatchObject implements IStartableCoroTask<T> {
	final lambda:NodeLambda<T>;

	/**
		Creates a new task using the provided `context` in order to execute `lambda`. The task doesn't
		run until it is started, usually with `dispatchStart`.
	**/
	public function new(context:Context, lambda:NodeLambda<T>, nodeStrategy:INodeStrategy#if coro.stack_traces, ?startPos:haxe.PosInfos#end) {
		this.lambda = lambda;
		super(context, nodeStrategy#if coro.stack_traces,startPos#end);
	}

	/**
		Starts this task through its context's dispatcher. Unless `start` set a caller before, this
		keeps the creation site as the task's call frame.
	**/
	@:allow(hxcoro)
	override function dispatchStart() {
		#if coro.stack_traces
		callFrameLocked = true;
		#end
		context.dispatchOrCall(this);
	}

	/**
		Starts this task right away on the calling thread instead of through its context's dispatcher,
		keeping the creation site as its call frame.

		This is only correct if the caller already runs on the dispatcher of this task's context, as
		`Coro.scope` does, which creates the task with the caller's own context.
	**/
	@:allow(hxcoro)
	function startUndispatched() {
		#if coro.stack_traces
		callFrameLocked = true;
		#end
		activate();
	}

	public function onDispatch() {
		activate();
	}

	/**
		Starts executing this task's `lambda`. Has no effect if the task has already been started or has completed.
	**/
	override public function doStart() {
		super.doStart();
		lambda(this, this);
	}
}