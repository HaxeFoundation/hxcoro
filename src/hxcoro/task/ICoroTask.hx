package hxcoro.task;

import haxe.coro.context.Context;
import haxe.Exception;
import haxe.exceptions.CancellationException;

/**
	A handle to a task producing a value of type `T`, as seen from outside the task.
**/
interface ICoroTask<T> {
	/**
		The task's unique id.
	**/
	var id(get, never):Int;

	/**
		The task's `Context`, which includes the task itself.
	**/
	var context(get, never):Context;

	/**
		Cancels the task and all its children. If `cause` is omitted, a new `CancellationException` is used.
	**/
	function cancel(?cause:CancellationException):Void;

	/**
		Suspends until the task completes, then returns its result or throws its error. Starts the task if
		it has not been started yet.
	**/
	@:coroutine function await(#if coro.stack_traces ?startPos:haxe.PosInfos #end):T;

	/**
		Returns the task's result. This does not wait for the task, and returns `null` if no result is available.
	**/
	function get():T;

	/**
		Returns the task's error, or `null` if there is none. A cancelled task reports its cancellation cause here.
	**/
	function getError():Exception;

	/**
		Returns `true` if the task has not yet completed or been cancelled. A task that was created but not
		started yet is considered active.
	**/
	function isActive():Bool;

	/**
		Registers `callback` to be invoked with the task's result and error once it completes. If the task
		has already completed, `callback` is invoked immediately.
	**/
	function onCompletion(callback:(result:T, error:Exception)->Void):Void;
}

/**
	A task that may have been created without being started, such as one created by `ICoroNode.lazy`.
**/
interface IStartableCoroTask<T> extends ICoroTask<T> {
	/**
		Starts executing the task. Has no effect if the task has already been started or has completed.

		When called from inside a task lambda, pass `node` as `caller` to include the calling task
		in exception stack traces.
	**/
	function start(?caller:ICoroNode#if coro.stack_traces, ?startPos:haxe.PosInfos #end):Void;
}
