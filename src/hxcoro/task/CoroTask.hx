package hxcoro.task;

import haxe.Exception;
import haxe.PosInfos;
import haxe.coro.CoroStackItem;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
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

class CoroTask<T> extends CoroBaseTask<T> implements IContinuation<T> implements IStackFrame {
	static public final CoroChildStrategy = new CoroChildStrategy();
	static public final CoroScopeStrategy = new CoroScopeStrategy();
	static public final CoroSupervisorStrategy = new CoroSupervisorStrategy();

	#if debug
	final callPos:Null<PosInfos>;
	#end

	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState = Running#if debug, ?callPos:PosInfos#end) {
		super(context, nodeStrategy, initialState);
		#if debug
		this.callPos = callPos;
		#end
	}

	public function doStart() {}

	/**
		Resumes the task with the provided `result` and `error`.
	**/
	public function resume(result:T, error:Exception) {
		if (error == null) {
			beginCompleting(result);
			checkCompletion();
		} else {
			beginCancelling(error);
			checkCompletion();
		}
	}

	/**
		@see `IStackFrame.callerFrame`
	**/
	public function callerFrame():Null<IStackFrame> {
		return parent is IStackFrame ? cast parent : null;
	}

	/**
		@see `IStackFrame.callerFrame`
	**/
	public function getStackItem() {
		return callPos == null ? null : CoroStackItem.PosInfo(callPos);
	}

	#if sys
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

class CoroTaskWithLambda<T> extends CoroTask<T> implements IDispatchObject implements IStartableCoroTask<T> {
	final lambda:NodeLambda<T>;

	/**
		Creates a new task using the provided `context` in order to execute `lambda`.
	**/
	public function new(context:Context, lambda:NodeLambda<T>, nodeStrategy:INodeStrategy, initialState:TaskState = Running#if debug, ?callPos:PosInfos#end) {
		this.lambda = lambda;
		super(context, nodeStrategy, Created#if debug,callPos#end);
		if (initialState == Running) {
			context.get(Dispatcher).dispatch(this);
		}
	}

	public function onDispatch() {
		start();
	}

	/**
		Starts executing this task's `lambda`. Has no effect if the task is already active or has completed.
	**/
	override public function doStart() {
		super.doStart();
		lambda(this, this);
	}
}