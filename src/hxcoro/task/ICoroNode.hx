package hxcoro.task;

import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.exceptions.CancellationException;
import hxcoro.task.ICoroTask;

/**
	The part of `ICoroNode` that gives access to a node's `Context` and creates child tasks.
**/
interface ICoroNodeWith {
	/**
		The node's `Context`, which includes the node itself.
	**/
	var context(get, null):NodeContext;

	/**
		Creates a child task to execute `lambda` and starts it immediately.

		Throws `InvalidTaskStateException` if this node has already completed.
	**/
	function async<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):ICoroTask<T>;

	/**
		Creates a child task to execute `lambda` without starting it. The task starts when its `start` or
		`await` method is called, or once this node has finished executing its own lambda or calls `awaitChildren`.

		Throws `InvalidTaskStateException` if this node has already completed.
	**/
	function lazy<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):IStartableCoroTask<T>;

	/**
		Returns a copy of the node's `Context` with `elements` added, which can be used to create child tasks.
	**/
	function with(...elements:IElement<Any>):NodeContext;

	/**
		Returns a copy of the node's `Context` with all `keys` removed, which can be used to create child tasks.
	**/
	function without(...keys:Key<Any>):NodeContext;
}

/**
	A task as seen from the coroutine it executes: it is passed to every `NodeLambda` and can be used
	to create and manage child tasks.
**/
@:coroutine.scope
interface ICoroNode extends ICoroNodeWith {
	/**
		The node's unique id.
	**/
	var id(get, never):Int;

	/**
		Starts any lazy children and suspends until all current children have completed. Children created
		afterwards are not affected.
	**/
	@:coroutine function awaitChildren():Void;

	/**
		Cancels the node and all its children. If `cause` is omitted, a new `CancellationException` is used.
	**/
	function cancel(?cause:CancellationException):Void;

	/**
		Cancels all current children of the node without cancelling the node itself. If `cause` is omitted,
		a new `CancellationException` is used.
	**/
	function cancelChildren(?cause:CancellationException):Void;
}
