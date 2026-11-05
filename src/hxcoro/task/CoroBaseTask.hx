package hxcoro.task;

import haxe.Exception;
import haxe.atomic.AtomicObject;
import haxe.coro.IContinuation;
import haxe.coro.IStackFrame;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.coro.continuations.FunctionContinuation;
import haxe.exceptions.CancellationException;
import hxcoro.concurrent.ThreadSafeCallbacks;
#if hxcoro.trace_tasks
import hxcoro.debug.TaskTrace;
#end
import hxcoro.elements.NonCancellable;
import hxcoro.task.AbstractTask;
import hxcoro.task.CoroTask;
import hxcoro.task.ICoroNode;
import hxcoro.task.ICoroTask;

/**
	Holds the continuations waiting for a task and resumes them with the task's outcome once it completes.
**/
class TaskContinuationManager extends ThreadSafeCallbacks<IContinuation<Any>, IContinuation<Any>, IContinuation<Any>> {
	public function new(task:CoroBaseTask<Any>) {
		super(handle -> handle.resume(task.get(), task.getError()), error -> task.reportCallbackError(error));
	}

	function createHandle(element:IContinuation<Any>) {
		return element;
	}
}

/**
	A callback registered with `CoroBaseTask.onCompletion`, which is unregistered by closing the handle.
**/
private class CompletionHandle implements ICompletionHandle {
	final manager:TaskContinuationManager;
	final cont:IContinuation<Any>;

	public function new(manager:TaskContinuationManager, cont:IContinuation<Any>) {
		this.manager = manager;
		this.cont = cont;
	}

	public function close() {
		manager.remove(cont);
	}
}

/**
	CoroBaseTask provides the basic functionality for coroutine tasks.
**/
abstract class CoroBaseTask<T> extends AbstractTask implements ICoroNode implements ICoroTask<T> implements IElement<CoroBaseTask<Any>> implements IStackFrame {
	/**
		The `Context` key under which a task stores itself in its own context.
	**/
	public static final key = new Key<CoroBaseTask<Any>>('Task');

	/**
		This task's immutable `Context`.
	**/
	public var context(get, null):Context;

	#if coro.stack_traces
	// Set once a start has been requested, after which `start` no longer changes the call frame.
	// The state can't tell this, because a task whose start was dispatched is still `Created`.
	var callFrameLocked:Bool;
	var startPos:Null<haxe.PosInfos>;
	var callerTask:Null<IStackFrame>;
	#end

	final awaitingContinuations:TaskContinuationManager;
	final awaitingChildContinuation:AtomicObject<Null<IContinuation<Any>>>;
	final nonCancellable:Bool;
	var result:Null<T>;

	// The same as `parent`, typed as what every task is.
	@:allow(hxcoro.debug)
	final parentTask:Null<CoroBaseTask<Any>>;

	// Called with each failed child that this task ignores as a supervisor.
	@:allow(hxcoro.Coro)
	var onChildFailure:Null<(child:ICoroTask<Any>, error:Exception) -> Void>;

	/**
		Creates a new task using the provided `context`. The task doesn't run until it is started.

		Throws `InvalidTaskStateException` if the task in `context`, the parent, has already completed.
	**/
	@:nullSafety(Off)
	public function new(context:Context, kind:TaskKind#if coro.stack_traces, ?startPos:haxe.PosInfos#end) {
		final parent = context.get(CoroBaseTask);
		parentTask = parent;
		awaitingContinuations = new TaskContinuationManager(this);
		awaitingChildContinuation = new AtomicObject(null);
		#if coro.stack_traces
		this.startPos = startPos;
		callFrameLocked = false;
		#end
		// A NonCancellable element marks the task it creates and goes no further: like the task itself,
		// which replaces the one of its parent in the context, it is consumed here rather than inherited.
		nonCancellable = context.get(NonCancellable) != null;
		this.context = context.clone().without(NonCancellable.key).with(this).set(CancellationToken, this);
		super(parent, kind#if hxcoro.trace_tasks, context.get(TaskTrace)#end);
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
		#if coro.stack_traces
		if (callerTask != null) {
			return callerTask;
		}
		return parentTask;
		#else
		return null;
		#end
	}

	/**
		@see `IStackFrame.getStackItem`
	**/
	public function getStackItem() {
		#if coro.stack_traces
		return startPos == null ? null : haxe.coro.CoroStackItem.PosInfo(startPos);
		#else
		return null;
		#end
	}

	/**
		Creates a lazy `Concurrent` child task to execute `lambda`. The child task does not execute until its `start`
		method is called. This occurs automatically once this task has finished execution, or right away if
		it already has.

		Throws `InvalidTaskStateException` if this task has already completed.
	**/
	public function lazy<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):IStartableCoroTask<T> {
		final task = new CoroTaskWithLambda(context, lambda, Concurrent#if coro.stack_traces, startPos#end);
		startLateLazyChild(task);
		return task;
	}

	/**
		Starts `child`, a lazy child that was just created, if this task has already finished its own work.
	**/
	@:allow(hxcoro.util)
	function startLateLazyChild(child:AbstractTask) {
		// startChildren and cancelChildren have run by then and no longer will. If this task is
		// cancelling, activate cancels the child. The child is already registered here, so if this
		// task's own work finishes after the check, startChildren or cancelChildren still sees it.
		switch (state.load()) {
			case Completing | Cancelling:
				child.requestActivation();
			case Created | Running | CancellationRequested | Completed | Cancelled:
		}
	}

	/**
		Creates a `Concurrent` child task to execute `lambda` and starts it automatically. It runs beside
		this task, and its outcome is reported to this task.

		Throws `InvalidTaskStateException` if this task has already completed.
	**/
	public function async<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):ICoroTask<T> {
		final task = new CoroTaskWithLambda<T>(context, lambda, Concurrent#if coro.stack_traces, startPos#end);
		task.requestActivation();
		return task;
	}

	/**
		Returns a copy of this task's `Context` with `elements` added, which can be used to start child tasks.
	**/
	public function with(...elements:IElement<Any>) {
		return context.with(...elements);
	}

	/**
		Returns a copy of this task's `Context` where all `keys` are unset, which can be used to start child tasks.
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
	public function awaitContinuation(cont:IContinuation<T>#if coro.stack_traces, ?startPos:haxe.PosInfos #end) {
		final caller = cont.context.get(CoroBaseTask);
		traceTask("await", caller);
		awaitingContinuations.add(cont);
		start(caller#if coro.stack_traces, startPos#end);
	}

	/**
		Starts executing this task. Has no effect if the task has already been started or has completed.

		The task might not have started running yet when this function returns.

		When called from inside a task lambda, pass `node` as `caller` to include the calling task
		in exception stack traces (e.g. `task1.start(node)`).
	**/
	public function start(?caller:ICoroNode#if coro.stack_traces, ?startPos:haxe.PosInfos #end) {
		#if coro.stack_traces
		if (!callFrameLocked) {
			callFrameLocked = true;
			if (caller is IStackFrame) {
				callerTask = cast caller;
			}
			this.startPos = startPos;
		}
		#end
		// A task that is no longer `Created` has started already. One that is still `Created` may have
		// been dispatched already too, which `requestActivation` takes care of.
		if (state.load() == Created) {
			requestActivation();
		}
	}

	override function ignoresCancellation() {
		return nonCancellable;
	}

	public function onCompletion(callback:(result:T, error:Exception)->Void):Null<ICompletionHandle> {
		final cont = new FunctionContinuation(context.clone(), callback);
		return awaitingContinuations.add(cont) == null ? null : new CompletionHandle(awaitingContinuations, cont);
	}

	/**
		Starts any lazy children and suspends this task until all its current children complete.
		Children can still be created after this function resumes and are not affected by this call.

		This is meant to be called by the node's own coroutine. Only one call can be in progress at a
		time: a second concurrent call, which is only possible through a node that was passed to
		another task, throws `InvalidTaskStateException`.
	**/
	@:coroutine public function awaitChildren() {
		traceTask("awaitChildren");
		startChildren();
		Coro.suspend(cont -> {
			switch (lockChildren()) {
				case 0:
					numActiveChildren.store(0);
					cont.callAsync();
				case activeChildren:
					// Register under the lock, so that the last child to complete sees the waiter.
					final registered = awaitingChildContinuation.compareExchange(null, cont) == null;
					numActiveChildren.store(activeChildren);
					if (!registered) {
						throw new InvalidTaskStateException("awaitChildren is already in progress on this task");
					}
			}
		});
	}

	/**
		Suspends the calling task until this task completes, starting this task if necessary. A
		cancelled caller stops waiting and resumes with its `CancellationException`.
	**/
	@:coroutine public function await(#if coro.stack_traces ?startPos:haxe.PosInfos #end):T {
		return Coro.suspendCancellable(cont -> {
			awaitContinuation(cont#if coro.stack_traces, startPos#end);
			// A cancelled awaiter leaves the awaiters, so that a long-lived task does not accumulate them.
			return _ -> awaitingContinuations.remove(cont);
		});
	}

	function handleAwaitingContinuations() {
		traceTask("handleAwaitingContinuations", null, null, true);
		awaitingContinuations.run();
		traceTask("handleAwaitingContinuations", null, null, false);
	}

	/**
		Rethrows `error` from a separately scheduled event. This keeps it from unwinding through the
		task machinery, which could leave other tasks waiting forever. A scheduler never runs an
		event synchronously, so this also holds when called outside of any dispatch.

		The exception then surfaces like any other uncaught exception on this task's dispatcher:
		a loop such as `CoroRun.run` throws it, and a thread pool reports it on its worker thread.
	**/
	function reportCallbackError(error:Exception) {
		context.scheduleFunction(0, () -> throw error);
	}

	function failureIgnored(error:Exception) {
		final supervisor = parentTask;
		final handler = supervisor?.onChildFailure;
		if (supervisor == null || handler == null) {
			return;
		}
		supervisor.traceTask("onChildFailure", this);
		try {
			handler(this, error);
		} catch (e:Exception) {
			supervisor.reportCallbackError(e);
		}
	}

	function childrenCompleted() {
		// Called after the children lock was released, so the waiter may take the lock again right away.
		final cont = awaitingChildContinuation.exchange(null);
		if (cont != null) {
			traceTask("childrenCompleted");
			cont.callAsync();
		}
	}

	function complete() {
		traceTask("complete", null, null, true);
		parent?.childCompletes(this);
		handleAwaitingContinuations();
		traceTask("complete", null, null, false);
	}
}
