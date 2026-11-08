package hxcoro.util;

import haxe.Exception;
import haxe.Int64;
import haxe.coro.IStackFrame;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.context.Context;
import haxe.coro.context.CallStackHandler;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;

/**
	Static extensions for `Context`.
**/
class ContextTools {
	/**
		Returns `true` if `context` has a `CancellationToken` element on which cancellation
		has been requested.
	**/
	static public function isCancellationRequested(context:Context) {
		final token = context.get(CancellationToken);
		return token != null && token.cancellationException != null;
	}

	/**
		Schedules `func` to be called after `ms` milliseconds using the scheduler of the
		context's `Dispatcher`, and returns the handle that can be closed to cancel the call.

		Throws if `context` has no `Dispatcher` element.
	**/
	static public inline function scheduleFunction(context:Context, ms:Int64, func:() -> Void) {
		return context.getOrRaise(Dispatcher).scheduler.schedule(ms, new FunctionContinuation(context, (_, _) -> func()));
	}

	/**
		Uses the context's `CallStackHandler`, if any, to build the coroutine call stack of
		`exc`, starting at `frame`.
	**/
	static public function setExceptionStack(context:Context, frame:IStackFrame, exc:Exception) {
		final handler = context.get(CallStackHandler);
		if (handler != null) {
			handler.startException(context, frame, exc);
			handler.buildCallStack(context, frame);
		}
	}

	/**
		Dispatches `obj` on the context's `Dispatcher`, or calls its `onDispatch` immediately
		if the context has no `Dispatcher` element.
	**/
	static public inline function dispatchOrCall(context:Context, obj:IDispatchObject) {
		final dispatcher = context.get(Dispatcher);
		if (dispatcher != null) {
			dispatcher.dispatch(obj);
		} else {
			obj.onDispatch();
		}
	}
}
