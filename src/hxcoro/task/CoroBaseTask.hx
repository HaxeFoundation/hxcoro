package hxcoro.task;

import hxcoro.concurrent.AtomicObject;
import haxe.coro.Mutex;
import hxcoro.components.NonCancellable;
import hxcoro.task.CoroTask;
import hxcoro.task.node.INodeStrategy;
import hxcoro.task.ICoroTask;
import hxcoro.task.AbstractTask;
import hxcoro.task.ICoroNode;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.context.Key;
import haxe.coro.context.IElement;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.cancellation.CancellationToken;

private class CoroTaskWith<T> implements ICoroNodeWith {
	public var context(get, null):Context;

	final task:CoroBaseTask<T>;

	public function new(context:Context, task:CoroBaseTask<T>) {
		this.context = context;
		this.task = task;
	}

	inline function get_context() {
		return context;
	}

	public function async<T>(lambda:NodeLambda<T>):ICoroTask<T> {
		final child = new CoroTaskWithLambda(context, lambda, CoroTask.CoroChildStrategy);
		context.get(Scheduler).scheduleObject(child);
		return child;
	}

	public function lazy<T>(lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new StartableCoroTask(context, lambda, CoroTask.CoroChildStrategy);
	}

	public function with(...elements:IElement<Any>) {
		return task.with(...elements);
	}

	public function without(...keys:Key<Any>) {
		return task.without(...keys);
	}
}

private class CoroKeys {
	static public final awaitingChildContinuation = new Key<IContinuation<Any>>("AwaitingChildContinuation");
}

private class CallbackContinuation<T> implements IContinuation<T> {
	final callback:(result:T, error:Exception)->Void;

	public var context (get, default) : Context;

	inline function get_context() {
		return context;
	}

	public function new(context, callback) {
		this.callback = callback;
		this.context  = context;
	}

	public function resume(value:T, error:Exception) {
		callback(value, error);
	}
}

class ArrayFixThisLater<T> {
	final array:Array<T>;
	final mutex:Mutex;

	public function new() {
		array = [];
		mutex = new Mutex();
	}

	public function push(v:T) {
		mutex.acquire();
		final r = array.push(v);
		mutex.release();
		return r;
	}

	public function exchangeIGuess() {
		mutex.acquire();
		final ret = array.copy();
		array.resize(0);
		mutex.release();
		return ret;
	}
}

/**
	CoroTask provides the basic functionality for coroutine tasks.
**/
abstract class CoroBaseTask<T> extends AbstractTask implements ICoroNode implements ICoroTask<T> implements ILocalContext implements IElement<CoroBaseTask<Any>> {
	/**
		This task's immutable `Context`.
	**/
	public var context(get, null):Context;

	/**
		This task's mutable local `Context`.
	**/
	public var localContext(get, null):Null<AdjustableContext>;

	final nodeStrategy:INodeStrategy;
	var result:Null<T>;
	var awaitingContinuations:ArrayFixThisLater<IContinuation<T>>;

	/**
		Creates a new task using the provided `context`.
	**/
	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState) {
		final parent = context.get(CoroTask);
		this.context = context.clone().with(this).set(CancellationToken, this);
		this.nodeStrategy = nodeStrategy;
		awaitingContinuations = new ArrayFixThisLater();
		super(parent, initialState);
	}

	inline function get_context() {
		return context;
	}

	inline function get_localContext() {
		if (localContext == null) {
			localContext = Context.create();
		}
		return localContext;
	}

	/**
		Returns this task's value, if any.
	**/
	public function get() {
		return result;
	}

	public function getKey() {
		return CoroTask.key;
	}

	/**
		Creates a lazy child task to execute `lambda`. The child task does not execute until its `start`
		method is called. This occurrs automatically once this task has finished execution.
	**/
	public function lazy<T>(lambda:NodeLambda<T>):IStartableCoroTask<T> {
		return new StartableCoroTask(context, lambda, CoroTask.CoroChildStrategy);
	}

	/**
		Creates a child task to execute `lambda` and starts it automatically.
	**/
	public function async<T>(lambda:NodeLambda<T>):ICoroTask<T> {
		final child = new CoroTaskWithLambda<T>(context, lambda, CoroTask.CoroChildStrategy);
		context.get(Scheduler).scheduleObject(child);
		return child;
	}

	/**
		Returns a copy of this tasks' `Context` with `elements` added, which can be used to start child tasks.
	**/
	public function with(...elements:IElement<Any>) {
		return new CoroTaskWith(context.clone().with(...elements), this);
	}

	/**
		Returns a copy of this tasks' `Context` where all `keys` are unset, which can be used to start child tasks.
	**/
	public function without(...keys:Key<Any>) {
		return new CoroTaskWith(context.clone().without(...keys), this);
	}

	/**
		Resumes `cont` with this task's outcome.

		If this task is no longer active, the continuation is resumed immediately. Otherwise, it is registered
		to be resumed upon completion.

		This function also starts this task if it has not been started yet.
	**/
	public function awaitContinuation(cont:IContinuation<T>) {
		switch (state.load()) {
			case Completed:
				cont.succeedSync(result);
			case Cancelled:
				cont.failSync(error);
			case _:
				awaitingContinuations.push(cont);
				start();
		}
	}

	override function cancel(?cause:CancellationException) {
		if (context.get(NonCancellable) != null || localContext.get(NonCancellable) != null) {
			return;
		}
		super.cancel(cause);
	}

	public function onCompletion(callback:(result:T, error:Exception)->Void) {
		switch (state.load()) {
			case Completed:
				callback(result, null);
			case Cancelled:
				callback(null, error);
			case _:
				awaitingContinuations.push(new CallbackContinuation(context.clone(), callback));
		}
	}

	/**
		Suspends this task until all its current children complete.

		Children can still be created after this function resumes and are not
		affected by this call.
	**/
	@:coroutine public function awaitChildren() {
		if (firstChild.load() == null) {
			localContext.get(CoroKeys.awaitingChildContinuation)?.callSync();
			return;
		}
		startChildren();
		Coro.suspend(cont -> localContext.set(CoroKeys.awaitingChildContinuation, cont));
	}

	/**
		Suspends this task until it completes.
	**/
	@:coroutine public function await():T {
		return Coro.suspend(awaitContinuation);
	}

	function handleAwaitingContinuations() {
		final succeed = switch (state.load()) {
				case Completed:
					true;
				case Cancelled:
					false;
				case state:
					throw new TaskException('Invalid state $state in handleAwaitingContinuations');
		}
		while (true) {
			final conts = awaitingContinuations.exchangeIGuess();
			if (conts.length == 0) {
				return;
			}
			for (cont in conts) {
				if (succeed) {
					cont.succeedAsync(result);
				} else {
					cont.failAsync(error);
				}
			}
		}
	}

	function childrenCompleted() {
		localContext.get(CoroKeys.awaitingChildContinuation)?.callSync();
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
