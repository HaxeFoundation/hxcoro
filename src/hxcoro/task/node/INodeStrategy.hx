package hxcoro.task.node;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import hxcoro.task.AbstractTask;
import hxcoro.task.CoroTask;

/**
	Defines how a task reacts to its own completion and to the outcome of its children. The `child*`
	callbacks are only invoked for children whose own strategy reports their outcome to the parent,
	which is the case for `CoroChildStrategy`.
**/
interface INodeStrategy {
	/**
		Called when `task` has reached its final state.
	**/
	function complete<T>(task:CoroBaseTask<T>):Void;

	/**
		Called when `child` of `task` completes successfully.
	**/
	function childSucceeds<T>(task:CoroBaseTask<T>, child:AbstractTask):Void;

	/**
		Called when `child` of `task` fails with `cause`, which is not a `CancellationException`.
	**/
	function childErrors<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:Exception):Void;

	/**
		Called when `child` of `task` is cancelled with `cause`.
	**/
	function childCancels<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:CancellationException):Void;
}
