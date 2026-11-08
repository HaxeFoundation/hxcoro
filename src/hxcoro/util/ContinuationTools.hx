package hxcoro.util;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.dispatchers.Dispatcher;

using hxcoro.util.DispatcherTools;

/**
	Static extensions for `IContinuation`.
**/
class ContinuationTools {
	/**
		Schedules `cont` to be resumed with `result`.

		Scheduled functions do not increase the call stack and might be executed in a different
		thread if the current dispatcher allows that.
	**/
	static public inline function succeedAsync<T>(cont:IContinuation<T>, result:T) {
		resumeAsync(cont, result, null);
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
