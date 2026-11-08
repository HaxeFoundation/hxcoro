package hxcoro.util;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;

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
	Static extensions for `Dispatcher`.
**/
class DispatcherTools {
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
