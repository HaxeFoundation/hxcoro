package hxcoro.util;

import haxe.Exception;
import haxe.Int64;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CancellationException;
import hxcoro.continuations.FunctionContinuation;

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
		cont.context.get(Dispatcher).dispatchContinuation(cont, result, error);
	}

}

class DispatcherConvenience {
	static public inline function dispatchFunction(dispatcher:Dispatcher, f:()->Void) {
		return dispatcher.dispatch(new FunctionDispatchObject(f));
	}

	static public inline function dispatchContinuation<T>(dispatcher: Dispatcher, cont:IContinuation<T>, result:T, error:Exception) {
		dispatcher.dispatch(new ContinuationDispatchObject(cont, result, error));
	}
}

class ContextConvenience {
	static public function isCancellationRequested(context:Context) {
		final token = context.get(CancellationToken);
		return token != null && token.isCancellationRequested();
	}

	static public inline function scheduleFunction(context:Context, ms:Int64, func:() -> Void) {
		return context.get(Dispatcher).scheduler.schedule(ms, new FunctionContinuation(context, (_, _) -> func()));
	}
}

class OtherConvenience {
	static public inline function orCancellationException(exc:Exception):CancellationException {
		return exc is CancellationException ? cast exc : new CancellationException();
	}

	static public inline function isCancellationRequested(ct:ICancellationToken) {
		return ct?.cancellationException != null;
	}

}