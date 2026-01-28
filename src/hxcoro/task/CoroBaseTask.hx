package hxcoro.task;

import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.AtomicObject;
import hxcoro.concurrent.BackOff;
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
import haxe.coro.dispatchers.Dispatcher;
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
		context.get(Dispatcher).dispatch(child);
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

enum abstract AggregatorState(Int) to Int {
	final Ready;
	final Modifying;
	final Finished;
}

class ThreadSafeAggregator<T> {
	var array:Null<Array<T>>;
	final func:T -> Void;
	final state:AtomicState<AggregatorState>;

	public function new(func:T -> Void) {
		array = null;
		this.func = func;
		state = new AtomicState(Ready);
	}

	// single threaded

	public function run() {
		while (true) {
			switch (state.compareExchange(Ready, Finished)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					// already done
					return;
			}
		}
		final array = array;
		if (array == null) {
			return;
		}
		this.array = null;
		for (element in array) {
			func(element);
		}
	}

	// thread-safe

	public function add(element:T) {
		while (true) {
			switch (state.compareExchange(Ready, Modifying)) {
				case Ready:
					break;
				case Modifying:
					BackOff.backOff();
				case Finished:
					func(element);
					return;
			}
		}
		array ??= [];
		array.push(element);
		state.store(Ready);
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
	var awaitingContinuations:ThreadSafeAggregator<IContinuation<T>>;
	var awaitingChildContinuation:AtomicObject<Null<IContinuation<Any>>>;

	/**
		Creates a new task using the provided `context`.
	**/
	public function new(context:Context, nodeStrategy:INodeStrategy, initialState:TaskState) {
		final parent = context.get(CoroTask);
		this.context = context.clone().with(this).set(CancellationToken, this);
		this.nodeStrategy = nodeStrategy;
		awaitingContinuations = new ThreadSafeAggregator<IContinuation<T>>(cont ->
			cont.resume(result, error)
		);
		awaitingChildContinuation = new AtomicObject(null);
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
		context.get(Dispatcher).dispatch(child);
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
		awaitingContinuations.add(cont);
		start();
	}

	override function cancel(?cause:CancellationException) {
		if (context.get(NonCancellable) != null || localContext.get(NonCancellable) != null) {
			return;
		}
		super.cancel(cause);
	}

	public function onCompletion(callback:(result:T, error:Exception)->Void) {
		awaitingContinuations.add(new CallbackContinuation(context.clone(), callback));
	}

	/**
		Suspends this task until all its current children complete.

		Children can still be created after this function resumes and are not
		affected by this call.
	**/
	@:coroutine public function awaitChildren() {
		startChildren();
		Coro.suspend(cont -> {
			// Preemptively set the value in case `childrenCompleted` happens.
			awaitingChildContinuation.store(cont);
			if (firstChild.load() == null) {
				// There's no child now and we know that none can appear because this
				// function is part of the single-threaded API. However, we don't know
				// if `childrenCompleted` might have occured, so we need to synchronize.
				if (awaitingChildContinuation.exchange(null) == cont) {
					cont.callAsync();
				}
				return;
			}
		});
	}

	/**
		Suspends this task until it completes.
	**/
	@:coroutine public function await():T {
		return Coro.suspend(awaitContinuation);
	}

	function handleAwaitingContinuations() {
		awaitingContinuations.run();
	}

	function childrenCompleted() {
		final cont = awaitingChildContinuation.exchange(null);
		cont?.callSync();
	}

	final inline function beginCompleting(result:T) {
		if (state.changeIf(Running, Completing)) {
			this.result = result;
			startChildren();
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
