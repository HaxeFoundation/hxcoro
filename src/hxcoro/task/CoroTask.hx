package hxcoro.task;

import haxe.Exception;
import haxe.atomic.AtomicInt;
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

	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState = Running#if coro.stack_traces, ?startPos:haxe.PosInfos#end) {
		super(context, nodeStrategy, initialState#if coro.stack_traces, startPos#end);
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
	// 1 once the start has been handed to the dispatcher
	final startScheduled:AtomicInt;

	/**
		Creates a new task using the provided `context` in order to execute `lambda`.
	**/
	public function new(context:Context, lambda:NodeLambda<T>, nodeStrategy:INodeStrategy, initialState:TaskState = Running#if coro.stack_traces, ?startPos:haxe.PosInfos#end) {
		this.lambda = lambda;
		startScheduled = new AtomicInt(0);
		super(context, nodeStrategy, Created#if coro.stack_traces,startPos#end);
		if (initialState == Running) {
			dispatchStart();
		}
	}

	/**
		Starts this task through its context's dispatcher, keeping its creation site as its call frame.
	**/
	@:allow(hxcoro.task.CoroBaseTask)
	function dispatchStart() {
		#if coro.stack_traces
		callFrameLocked = true;
		#end
		scheduleStart(null);
	}

	/**
		Starts this task, at most once. If `starter` is a task on the same dispatcher, it is already
		running there, so this task starts right away. Otherwise, the start is handed to this task's
		dispatcher. A start that has been handed over already is left to the dispatcher, so that a
		task that is awaited from another dispatcher still runs where its context says.
	**/
	override function scheduleStart(starter:Null<AbstractTask>) {
		if (startScheduled.compareExchange(0, 1) != 0) {
			return;
		}
		final starterTask:Null<CoroBaseTask<Any>> = Std.downcast(starter, CoroBaseTask);
		if (starterTask != null && starterTask.context.get(Dispatcher) == context.get(Dispatcher)) {
			activate();
		} else {
			context.dispatchOrCall(this);
		}
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