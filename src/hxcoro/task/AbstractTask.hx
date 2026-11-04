package hxcoro.task;

import haxe.Exception;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationToken;
import haxe.exceptions.CancellationException;
import haxe.atomic.AtomicInt;
import hxcoro.concurrent.AtomicRef;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;
import hxcoro.task.StopCause;

/**
	The lifecycle state of a task.
**/
@:using(AbstractTask.TaskStateTools)
enum abstract TaskState(Int) to Int {
	/**
		The task has been created but not started.
	**/
	final Created;

	/**
		The task has been started and its own work has not finished yet.
	**/
	final Running;

	/**
		Cancellation of the task has been requested, but its own work has not finished yet.
	**/
	final CancellationRequested;

	/**
		The task's own work has finished with a result and it is waiting for its children to complete.
	**/
	final Completing;

	/**
		The task and all its children have completed successfully. This is a final state.
	**/
	final Completed;

	/**
		The task's own work has failed, been cancelled or never started, and it is waiting for its
		children to complete.
	**/
	final Cancelling;

	/**
		The task has completed with an error, which `getError` returns. This is a final state.
	**/
	final Cancelled;
}

private class TaskStateTools {
	static public function toString(state:TaskState) {
		return switch (state) {
			case Created: "Created";
			case Running: "Running";
			case CancellationRequested: "CancellationRequested";
			case Completing: "Completing";
			case Completed: "Completed";
			case Cancelling: "Cancelling";
			case Cancelled: "Cancelled";
		}
	};
}

/**
	Raised as a task's error when the task detects an invalid internal state.
**/
class TaskException extends Exception {}

/**
	AbstractTask is the base class for tasks which manages its `TaskState` and children.

	Developer note: it should have no knowledge of any asynchronous behavior or anything related to coroutines,
	and should be kept in a state where it could even be moved outside the hxcoro package. Also, `state` should
	be treated like a truly private variable and only be modified from within this class.
**/
abstract class AbstractTask implements ICancellationToken {
	static final atomicId = new AtomicInt(1); // start with 1 so we can use 0 for "no task" situations

	final parent:Null<AbstractTask>;

	final cancellationManager:TaskCancellationManager;
	final stopCause:AtomicRef<Null<StopCause>>;
	final state:AtomicState<TaskState>;
	final kind:TaskKind;

	/**
		The task's unique id, assigned on creation.
	**/
	public var id(get, null):Int;

	/**
		`null` if the task is not cancelling, otherwise its error as a `CancellationException`.
	**/
	public var cancellationException(get, never):Null<CancellationException>;

	// children

	final numActiveChildren:AtomicInt;
	var firstChild:Null<AbstractTask>;
	var nextSibling:Null<AbstractTask>;
	var previousSibling:Null<AbstractTask>;

	function get_cancellationException() {
		if (!isCancelling()) {
			return null;
		}
		return switch (stopCause.load()) {
			case null: null;
			case Cancellation(cause) | Failure(_, cause): cause;
		}
	}

	public inline function get_id() {
		return id;
	}

	/**
		Creates a new task of `kind` in the `Created` state.
	**/
	public function new(parent:Null<AbstractTask>, kind:TaskKind) {
		id = atomicId.add(1);
		this.parent = parent;
		this.kind = kind;
		state = new AtomicState(Created);
		stopCause = new AtomicRef(null);
		cancellationManager = @:nullSafety(Off) new TaskCancellationManager(this);
		numActiveChildren = new AtomicInt(0);
		if (parent != null) {
			parent.addChild(this);
		}
	}

	/**
		Returns the task's error value if it has completed with one, or `null` otherwise.
	**/
	public function getError():Null<Exception> {
		// The state is the authority: a cause can be recorded on a task that completes successfully
		// anyway, or that is still cancelling, and in neither case is it the task's outcome.
		if (state.load() != Cancelled) {
			return null;
		}
		return switch (stopCause.load()) {
			case null: null;
			case cause: errorOf(cause);
		}
	}

	/**
		Returns the exception that `cause` reports as the task's error: the failure's error, or the
		cancellation's exception.
	**/
	static function errorOf(cause:StopCause):Exception {
		return switch (cause) {
			case Cancellation(cause): cause;
			case Failure(error, _): error;
		}
	}

	/**
		Returns `true` if the task has completed because it was cancelled.
	**/
	public function isCancelled() {
		return state.load() == Cancelled && stopCause.load().match(Cancellation(_));
	}

	/**
		Returns `true` if the task has completed because its own work or one of its children failed.
	**/
	public function isFailed() {
		return state.load() == Cancelled && stopCause.load().match(Failure(_, _));
	}

	/**
		Initiates cancellation of this task and all its children.

		If `cause` is provided, it is set as this task's error value and used to cancel all children.

		If the task cannot be cancelled or has already been cancelled, this function only checks if the
		task has completed and initiates the appropriate behavior.
	**/
	public function cancel(?cause:CancellationException) {
		cause ??= new CancellationException();
		doCancel(cause);
	}

	/**
		Requests cancellation of this task with `cause`. Unlike `fail`, this can be prevented, which
		is what `NonCancellable` does by overriding it.

		The state is the authority on whether the task is cancelling. The cause is only meaningful once
		the state says so, which is why it is recorded before any transition to a cancelling state. A
		cancellation never replaces a cause that is already recorded.
	**/
	function doCancel(cause:CancellationException) {
		stopCause.compareExchange(null, Cancellation(cause));
		requestStop();
	}

	/**
		Fails this task with `error`, which cannot be prevented. A failure replaces a cancellation that
		was requested before, but not an earlier failure.
	**/
	function fail(error:Exception) {
		failWith(Failure(error, cancellationFor(error)));
	}

	/**
		Fails this task with `failure`, which is a `Failure` and may be the one of a child. It is reused as
		this task's cause, so that the children of both are cancelled with the same cause.
	**/
	function failWith(failure:StopCause) {
		recordFailure(failure);
		requestStop();
	}

	/**
		Creates the `CancellationException` that the children of a task failing with `error` are
		cancelled with. It is always a new exception, so that a child does not mistake the parent's
		failure for its own cancellation cause, e.g. a `TimeoutException`. It carries `error`'s stack
		where supported.
	**/
	static function cancellationFor(error:Exception):CancellationException {
		final cause = new CancellationException();
		#if !js
		cause.stack = error.stack;
		#end
		return cause;
	}

	/**
		Records `failure` as this task's cause. Returns `true` if it is now the cause, or `false` if a
		failure was recorded before, which is kept.
	**/
	function recordFailure(failure:StopCause) {
		while (true) {
			final current = stopCause.load();
			switch (current) {
				case Failure(_, _):
					return false;
				case null:
					if (stopCause.compareExchange(current, failure) == current) {
						return true;
					}
				case Cancellation(cause):
					// The children and the callbacks have received `cause` already, so it stays.
					if (stopCause.compareExchange(current, Failure(errorOf(failure), cause)) == current) {
						return true;
					}
			}
			BackOff.backOff();
		}
	}

	/**
		Moves this task to a cancelling state after its cause was recorded. The thread whose transition
		succeeds runs `beginCancellation`, so it runs exactly once.
	**/
	function requestStop() {
		while (true) {
			final current = state.load();
			switch (current) {
				case Created | Running | Completing:
					// A running task has to finish its own work first. A created task never starts it.
					final next = current == Running ? CancellationRequested : Cancelling;
					if (state.compareExchange(current, next) == current) {
						beginCancellation();
						break;
					}
				case CancellationRequested | Cancelling | Completed | Cancelled:
					// Already cancelling, or the outcome is final.
					break;
			}
		}
		checkCompletion();
	}

	/**
		Called by the thread that moved this task to a cancelling state. Runs the cancellation callbacks,
		which has no effect after the first time, and cancels all current children.
	**/
	function beginCancellation() {
		cancellationManager.run();
		cancelChildren(cancellationException);
	}

	/**
		Called when the task's own work has finished successfully. Returns `true` if the task is now
		completing with a result, or `false` if cancellation was requested before.

		The caller is responsible for calling `checkCompletion` afterwards.
	**/
	final function ownWorkSucceeds() {
		while (true) {
			switch (state.load()) {
				case Running:
					if (state.compareExchange(Running, Completing) == Running) {
						return true;
					}
				case CancellationRequested:
					if (state.compareExchange(CancellationRequested, Cancelling) == CancellationRequested) {
						// Cancel children that were created after the cancellation request.
						beginCancellation();
						return false;
					}
				case Created | Completing | Cancelling | Completed | Cancelled:
					return false;
			}
		}
	}

	/**
		Called when the task's own work has thrown `error`, which cannot be prevented.

		If nobody requested cancellation, this is a failure, whatever the type of `error`. If
		cancellation was requested, a `CancellationException` is the unwinding that was asked for and
		keeps the requested cause, while any other error means something broke while unwinding and
		becomes the cause instead.

		The caller is responsible for calling `checkCompletion` afterwards.
	**/
	final function ownWorkFails(error:Exception) {
		while (true) {
			final current = state.load();
			switch (current) {
				case Running:
					recordFailure(Failure(error, cancellationFor(error)));
					if (state.compareExchange(Running, Cancelling) == Running) {
						beginCancellation();
						return;
					}
				case CancellationRequested:
					if (!(error is CancellationException)) {
						recordFailure(Failure(error, cancellationFor(error)));
					}
					if (state.compareExchange(CancellationRequested, Cancelling) == CancellationRequested) {
						beginCancellation();
						return;
					}
				case Created | Completing | Cancelling | Completed | Cancelled:
					return;
			}
		}
	}

	/**
		Returns `true` if the task is still active. Note that a task that was created but not started yet
		is considered to be active.
	**/
	public function isActive() {
		return switch (state.load()) {
			case Completed | Cancelled:
				false;
			case _:
				true;
		}
	}

	/**
		Returns `true` if cancellation has been requested or the task has failed. This remains `true`
		after the task has completed.
	**/
	public function isCancelling() {
		return switch (state.load()) {
			case CancellationRequested | Cancelling | Cancelled:
				true;
			case Created | Running | Completing | Completed:
				false;
		}
	}

	public function onCancellationRequested(callback:ICancellationCallback):Null<ICancellationHandle> {
		return cancellationManager.add(callback);
	}

	/**
		Moves this task from `Created` to `Running` and runs its own work, on the calling thread. Has no
		effect if the task has already been started or has completed.
	**/
	final function activate() {
		if (state.compareExchange(Created, Running) == Created) {
			// Check if parent is cancelling and attempt to cancel this task before starting.
			// If the task has NonCancellable context, doCancel() will return early and
			// the task stays Running, allowing it to start.
			if (parent != null && parent.isCancelling()) {
				cancel();
			}
			// Only start if the task wasn't successfully cancelled
			if (state.load() == Running) {
				runOwnWork();
			} else if (state.compareExchange(CancellationRequested, Cancelling) == CancellationRequested) {
				// The task's own work never starts.
				checkCompletion();
			}
		}
	}

	/**
		Arranges for `activate` to be called where this task is supposed to run, which may be right away.

		Calling this more than once is harmless, because `activate` only starts a created task.
	**/
	abstract function requestActivation():Void;

	function lockChildren() {
		while (true) {
			switch (numActiveChildren.load()) {
				case -1:
					// wait
				case old:
					if (numActiveChildren.compareExchange(old, -1) == old) {
						return old;
					}
			}
			BackOff.backOff();
		}
	}

	/**
		Cancels all current children of this task, using `cause` as the reason.

		This task itself is not cancelled and continues to run. Newly created children
		are also not affected by this.
	**/
	public function cancelChildren(?cause:CancellationException) {
		switch (lockChildren()) {
			case 0:
				numActiveChildren.store(0);
				return;
			case activeChildren:
				cause ??= new CancellationException();
				// Collect children, then unlock and cancel them
				final children = getCurrentChildren();
				numActiveChildren.store(activeChildren);
				for (child in children) {
					child.cancel(cause);
				}
		}
	}

	function startChildren() {
		switch (lockChildren()) {
			case 0:
				numActiveChildren.store(0);
				return;
			case activeChildren:
				// Collect children, then unlock and start them
				final children = getCurrentChildren();
				numActiveChildren.store(activeChildren);
				for (child in children) {
					child.requestActivation();
				}
		}
	}

	function getCurrentChildren() {
		// Only safe to call if numActiveChildren is locked
		final children:Array<AbstractTask> = [];
		var child = firstChild;
		while (child != null) {
			children.push(child);
			child = child.nextSibling;
		}
		return children;
	}

	final function checkCompletion() {
		// The final transition happens while the children lock is held, so that no child can attach
		// to a task that is about to complete. `complete` runs after the lock is released, because it
		// resumes other code.
		final completed = switch (lockChildren()) {
			case 0:
				switch (state.load()) {
					case Created | Running | CancellationRequested:
						// The task's own work has not finished yet.
						false;
					case Completing:
						// If this fails, the task was cancelled concurrently and whoever did that checks again.
						state.compareExchange(Completing, Completed) == Completing;
					case Cancelling:
						state.compareExchange(Cancelling, Cancelled) == Cancelling;
					case Completed | Cancelled:
						false;
				}
			case activeChildren:
				numActiveChildren.store(activeChildren);
				return;
		}
		numActiveChildren.store(0);
		if (completed) {
			complete();
		}
	}

	function setInternalException(reason:String) {
		fail(new TaskException(reason));
	}

	/**
		Runs this task's own work. Called by `activate` once the task is `Running`.
	**/
	abstract function runOwnWork():Void;

	abstract function complete():Void;

	/**
		Called after the last child completed and the children lock was released.
	**/
	abstract function childrenCompleted():Void;

	/**
		Reports `error`, which a callback registered with this task threw, without unwinding
		through the task machinery.
	**/
	@:allow(hxcoro.task.TaskCancellationManager)
	@:allow(hxcoro.task.TaskContinuationManager)
	abstract function reportCallbackError(error:Exception):Void;

	/**
		Called when `child` fails with `failure`. Supervisors ignore the failure, all other tasks inherit
		it, also while they are already cancelling.
	**/
	function childErrors(child:AbstractTask, failure:StopCause) {
		switch (kind) {
			case Concurrent | Sequential:
				switch (state.load()) {
					case Created | Running | Completing | CancellationRequested | Cancelling:
						failWith(failure);
					case Completed | Cancelled:
				}
			case SequentialSupervisor:
		}
	}

	/**
		Called when `child` is cancelled with `cause`. Only concurrent tasks are cancelled along with it.
	**/
	function childCancels(child:AbstractTask, cause:CancellationException) {
		switch (kind) {
			case Concurrent:
				cancel(cause);
			case Sequential | SequentialSupervisor:
		}
	}

	// called from child

	function childCompletes(child:AbstractTask, processResult:Bool) {
		if (processResult) {
			switch (child.state.load()) {
				case Completed:
				case Cancelled:
					switch (child.stopCause.load()) {
						case Cancellation(cause):
							childCancels(child, cause);
						case failure = Failure(_, _):
							childErrors(child, failure);
						case null:
							return setInternalException('No cause on cancelled child in childCompletes');
					}
				case state:
					return setInternalException('Invalid state $state in childCompletes');
			}
		}
		switch (lockChildren()) {
			case 0:
				numActiveChildren.store(0);
				return setInternalException('numActiveChildren is already 0 in childCompletes');
			case 1:
				firstChild = null;
				numActiveChildren.store(0);
				// Resumes the awaitChildren waiter, outside the lock so that it may take it right away.
				childrenCompleted();
				checkCompletion();
			case activeChildren:
				final next = child.nextSibling;
				final prev = child.previousSibling;
				if (next != null) {
					next.previousSibling = prev;
				}
				if (prev != null) {
					prev.nextSibling = next;
				}
				if (firstChild == child) {
					firstChild = next;
				}
				child.nextSibling = null;
				child.previousSibling = null;
				numActiveChildren.store(activeChildren - 1);
		}
	}

	function addChild(child:AbstractTask) {
		final activeChildren = lockChildren();
		if (firstChild != null) {
			child.nextSibling = firstChild;
			firstChild.previousSibling = child;
		}
		firstChild = child;
		numActiveChildren.store(activeChildren + 1);
	}
}
