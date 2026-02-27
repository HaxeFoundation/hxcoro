package hxcoro.continuations;

import haxe.coro.CoroStackItem;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;

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
}
