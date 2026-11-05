package hxcoro.continuations;

import haxe.coro.CoroStackItem;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
#if hxcoro.trace_tasks
import hxcoro.debug.TaskTrace;
import hxcoro.task.CoroBaseTask;
#end

/**
	Abstract base class for continuation wrappers (`RacingContinuation`,
	`CancellingContinuation`, `TimeoutContinuation`) that delegate to an inner
	continuation and implement `IStackFrame` by forwarding to that continuation.

	Provides shared implementations of `context`, `callerFrame()`, and
	`getStackItem()` that all three concrete continuation classes need.
**/
abstract class StackFrameContinuation<T> extends SuspensionResult<T> implements IContinuation<T> implements IStackFrame {
	final cont: IContinuation<T>;

	public var context(get, never): Context;

	function get_context() {
		return cont.context;
	}

	function new(cont: IContinuation<T>) {
		super(Pending);
		this.cont = cont;
	}

	public function callerFrame(): Null<IStackFrame> {
		return cont.asStackFrame();
	}

	public function getStackItem(): Null<CoroStackItem> {
		return null;
	}

	#if hxcoro.trace_tasks
	// The wrapped coroutine body runs inside `onDispatch`, from its resumption to its next suspension,
	// which this reports to the task's TaskTrace as the `run` method.
	inline function traceRun(enter:Bool) {
		final task = context.get(CoroBaseTask);
		final trace = context.get(TaskTrace);
		if (task != null && trace != null) {
			trace.log(task, "run", null, null, enter);
		}
	}
	#end
}
