package hxcoro.util;

import haxe.Exception;
import haxe.Int64;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.context.Context;
import haxe.coro.context.ExceptionHandler;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CancellationException;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroTask;
import hxcoro.task.NodeLambda;

private class FunctionDispatchObject implements IDispatchObject {
	final func : ()->Void;

	public function new(func) {
		this.func = func;
	}

	public function onDispatch() {
		func();
	}
}

private class ContinuationDispatchObject<T> implements IDispatchObject {
	public final cont:IContinuation<T>;
	public final result:Null<T>;
	public final error:Null<Exception>;

	public function new(cont:IContinuation<T>, result:Null<T>, error:Null<Exception>) {
		this.cont = cont;
		this.result = result;
		this.error = error;
	}

	public function onDispatch() {
		cont.resume(result, error);
	}
}

/**
	A set of convenience functions for working with hxcoro data.
**/
class ContinuationConvenience {
	/**
		Resumes `cont` with `result` immediately.
	**/
	static public inline function succeedSync<T>(cont:IContinuation<T>, result:T) {
		cont.resume(result, null);
	}

	/**
		Resumes `cont` with exception `error` immediately.
	**/
	static public inline function failSync<T>(cont:IContinuation<T>, error:Exception) {
		cont.resume(null, error);
	}

	/**
		Schedules `cont` to be resumed with `result`.

		Scheduled functions do not increase the call stack and might be executed in a different
		thread if the current dispatcher allows that.
	**/
	static public inline function succeedAsync<T>(cont:IContinuation<T>, result:T) {
		resumeAsync(cont, result, null);
	}

	/**
		Schedules `cont` to be resumed with exception `error`.

		Scheduled functions do not increase the call stack and might be executed in a different
		thread if the current dispatcher allows that.
	**/
	static public inline function failAsync<T>(cont:IContinuation<T>, error:Exception) {
		resumeAsync(cont, null, error);
	}

	/**
		Calls `cont` without any values immediately.
	**/
	static public inline function callSync<T>(cont:IContinuation<T>) {
		cont.resume(null, null);
	}

	/**
		Schedules `cont` to be resumed without any values.

		Scheduled functions do not increase the call stack and might be executed in a different
		thread if the current dispatcher allows that.
	**/
	static public inline function callAsync<T>(cont:IContinuation<T>) {
		resumeAsync(cont, null, null);
	}

	/**
		Schedules `cont` to be resumed with result `result` and exception `error`.

		Scheduled functions do not increase the call stack and might be executed in a different
		thread if the current dispatcher allows that.
	**/
	static public inline function resumeAsync<T>(cont:IContinuation<T>, result:Null<T>, error:Null<Exception>) {
		cont.context.getOrRaise(Dispatcher).dispatchContinuation(cont, result, error);
	}

	/**
		Returns `cont` as an `IStackFrame` if it implements that interface, or `null` otherwise.
	**/
	static public inline function asStackFrame<T>(cont:IContinuation<T>):Null<IStackFrame> {
		return if (cont is IStackFrame) {
			cast cont;
		} else {
			null;
		}
	}
}

/**
	Static extensions for `Dispatcher`.
**/
class DispatcherConvenience {
	/**
		Dispatches a call to `f` on `dispatcher`.
	**/
	static public inline function dispatchFunction(dispatcher:Dispatcher, f:()->Void) {
		return dispatcher.dispatch(new FunctionDispatchObject(f));
	}

	/**
		Dispatches the resumption of `cont` with `result` and `error` on `dispatcher`.
	**/
	static public inline function dispatchContinuation<T>(dispatcher: Dispatcher, cont:IContinuation<T>, result:Null<T>, error:Null<Exception>) {
		dispatcher.dispatch(new ContinuationDispatchObject(cont, result, error));
	}
}

/**
	Static extensions for `Context`.
**/
class ContextConvenience {
	/**
		Returns `true` if `context` has a `CancellationToken` element on which cancellation
		has been requested.
	**/
	static public function isCancellationRequested(context:Context) {
		final token = context.get(CancellationToken);
		return token != null && token.isCancellationRequested();
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
		Starts executing `lambda` in a new task using `context`. If `context` contains a task,
		the new task becomes its child.
	**/
	static public function async<T>(context:Context, lambda:NodeLambda<T>):ICoroTask<T> {
		final task = new CoroTaskWithLambda<T>(context, lambda, CoroTask.CoroChildStrategy, Created);
		task.dispatchStart();
		return task;
	}

	/**
		Like `async`, but the task does not run `lambda` until it is started.
	**/
	static public function lazy<T>(context:Context, lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new CoroTaskWithLambda(context, lambda, CoroTask.CoroChildStrategy, Created);
	}

	/**
		Uses the context's `ExceptionHandler`, if any, to build the coroutine call stack of
		`exc`, starting at `frame`.
	**/
	static public function setExceptionStack(context:Context, frame:IStackFrame, exc:Exception) {
		final handler = context.get(ExceptionHandler);
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

/**
	Miscellaneous static extensions.
**/
class OtherConvenience {
	/**
		Returns `exc` if it is a `CancellationException`, or otherwise a new
		`CancellationException` that carries the stack of `exc` where supported.
	**/
	static public inline function orCancellationException(exc:Null<Exception>):CancellationException {
		return if (exc is CancellationException) {
			cast exc;
		 } else {
			final cancellationException = new CancellationException();
			#if !js
			if (exc != null) {
				cancellationException.stack = exc.stack;
			}
			#end
			cancellationException;
		 }
	}

	/**
		Returns `true` if `ct` is not `null` and has a cancellation exception set.
	**/
	static public inline function isCancellationRequested(ct:ICancellationToken) {
		return ct?.cancellationException != null;
	}

}