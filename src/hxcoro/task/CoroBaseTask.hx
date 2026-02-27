package hxcoro.task;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.coro.continuations.FunctionContinuation;
import haxe.exceptions.CancellationException;
import hxcoro.concurrent.ThreadSafeCallbacks;
import hxcoro.elements.NonCancellable;
import hxcoro.task.AbstractTask;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroNode;
import hxcoro.task.ICoroTask;
import hxcoro.task.node.INodeStrategy;

class TaskContinuationManager extends ThreadSafeCallbacks<IContinuation<Any>, IContinuation<Any>, IContinuation<Any>> {
	public function new(task:CoroBaseTask<Any>) {
		super(handle -> handle.resume(task.get(), task.getError()));
	}

	function createHandle(element:IContinuation<Any>) {
		return element;
	}
}

/**
	CoroTask provides the basic functionality for coroutine tasks.
**/
abstract class CoroBaseTask<T> extends AbstractTask implements ICoroNode implements ICoroTask<T> implements IElement<CoroBaseTask<Any>> implements IStackFrame {
	public static final key = new Key<CoroBaseTask<Any>>('Task');

	/**
		This task's immutable `Context`.
	**/
	public var context(get, null):Context;

	#if debug
	var startPos:Null<haxe.PosInfos>;
	var callerTask:Null<IStackFrame>;

	function setCallerTask(caller:CoroBaseTask<Any>) {
		if (caller != parent && caller != this) {
			callerTask = caller;
		}
	}
	#end

	final nodeStrategy:INodeStrategy;
	final awaitingContinuations:TaskContinuationManager;
	var awaitingChildContinuation:Null<IContinuation<Any>>;
	var result:Null<T>;

	/**
		Creates a new task using the provided `context`.
	**/
	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState) {
		final parent = context.get(CoroBaseTask);
		this.context = context.clone().with(this).set(CancellationToken, this);
		this.nodeStrategy = nodeStrategy;
		awaitingContinuations = new TaskContinuationManager(this);
		super(parent, initialState);
	}

	inline function get_context() {
		return context;
	}

	/**
		Returns this task's value, if any.
	**/
	public function get() {
		return result;
	}

	public function getKey() {
		return key;
	}


	/**
		@see `IStackFrame.callerFrame`
	**/
	public function callerFrame():Null<IStackFrame> {
		#if debug
		if (callerTask != null) {
			return callerTask;
		}
		return parent is IStackFrame ? cast parent : null;
		#else
		return null;
		#end
	}

	/**
		@see `IStackFrame.callerFrame`
	**/
	public function getStackItem() {
		#if debug
		return startPos == null ? null : haxe.coro.CoroStackItem.PosInfo(startPos);
		#else
		return null;
		#end
	}

	/**
		Creates a lazy child task to execute `lambda`. The child task does not execute until its `start`
		method is called. This occurrs automatically once this task has finished execution.
	**/
	public function lazy<T>(lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new CoroTaskWithLambda(context, lambda, CoroTask.CoroChildStrategy, Created#if debug, null#end);
	}

	/**
		Creates a child task to execute `lambda` and starts it automatically.
	**/
	public function async<T>(lambda:NodeLambda<T>#if debug, ?startPos:haxe.PosInfos#end):ICoroTask<T> {
		return new CoroTaskWithLambda<T>(context, lambda, CoroTask.CoroChildStrategy#if debug, startPos#end);
	}

	/**
		Returns a copy of this tasks' `Context` with `elements` added, which can be used to start child tasks.
	**/
	public function with(...elements:IElement<Any>) {
		return context.with(...elements);
	}

	/**
		Returns a copy of this tasks' `Context` where all `keys` are unset, which can be used to start child tasks.
	**/
	public function without(...keys:Key<Any>) {
		return context.without(...keys);
	}

	/**
		Resumes `cont` with this task's outcome.

		If this task is no longer active, the continuation is resumed immediately. Otherwise, it is registered
		to be resumed upon completion.

		This function also starts this task if it has not been started yet.
	**/
	public function awaitContinuation(cont:IContinuation<T>) {
		awaitingContinuations.add(cont);
		activate();
	}

	/**
		Starts executing this task. Has no effect if the task is already active or has completed.

		When called from inside a task lambda, pass `node` as `caller` to include the calling task
		in exception stack traces (e.g. `task1.start(node)`).
	**/
	public function start(?caller:ICoroNode#if debug, ?startPos:haxe.PosInfos #end) {
		#if debug
		final isFirstPosition = this.startPos == null;
		if (isFirstPosition && startPos != null) {
			this.startPos = startPos;
		}
		if (isFirstPosition && caller is CoroBaseTask) {
			setCallerTask(cast caller);
		}
		#end
		activate();
	}

	override function doCancel(error:Exception) {
		if (context.get(NonCancellable) != null) {
			return;
		}
		super.doCancel(error);
	}

	public function onCompletion(callback:(result:T, error:Exception)->Void) {
		awaitingContinuations.add(new FunctionContinuation(context.clone(), callback));
	}

	/**
		Suspends this task until all its current children complete.

		Children can still be created after this function resumes and are not
		affected by this call.
	**/
	@:coroutine public function awaitChildren() {
		startChildren();
		Coro.suspend(cont -> {
			switch (lockChildren()) {
				case 0:
					cont.callAsync();
					numActiveChildren.store(0);
				case activeChildren:
					awaitingChildContinuation = cont;
					numActiveChildren.store(activeChildren);
			}
		});
	}

	/**
		Suspends this task until it completes.
	**/
	@:coroutine public function await(#if debug ?startPos:haxe.PosInfos #end):T {
		#if debug
		final isFirstPosition = this.startPos == null;
		if (isFirstPosition && startPos != null) {
			this.startPos = startPos;
		}
		#end
		return Coro.suspend(cont -> {
			#if debug
			if (isFirstPosition) {
				final caller = cont.context.get(CoroBaseTask);
				if (caller != null) {
					setCallerTask(caller);
				}
			}
			#end
			awaitContinuation(cont);
		});
	}

	function handleAwaitingContinuations() {
		awaitingContinuations.run();
	}

	function childrenCompleted() {
		// The numActiveChildren lock is active while we're here, so this modification is safe
		final cont = awaitingChildContinuation;
		if (cont != null) {
			awaitingChildContinuation = null;
			cont.callAsync();
		}
	}

	final function beginCompleting(result:T) {
		if (state.compareExchange(Running, Completing) == Running) {
			this.result = result;
			startChildren();
		}
	}

	final function beginCancelling(error:Exception) {
		if (state.compareExchange(Running, Cancelling) == Running) {
			doCancel(error);
		}
	}

	// strategy dispatcher

	function complete() {
		nodeStrategy.complete(this);
	}

	function childSucceeds(child:AbstractTask) {
		nodeStrategy.childSucceeds(this, child);
	}

	function childErrors(child:AbstractTask, cause:Exception) {
		nodeStrategy.childErrors(this, child, cause);
	}

	function childCancels(child:AbstractTask, cause:CancellationException) {
		nodeStrategy.childCancels(this, child, cause);
	}
}
