package hxcoro.task;

import haxe.Exception;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationToken;
import haxe.exceptions.CancellationException;
import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicObject;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;

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
	final error:AtomicObject<Null<Exception>>;
	final state:AtomicState<TaskState>;

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
		return switch (error.load()) {
			case null: null;
			case error: error.orCancellationException();
		}
	}

	public inline function get_id() {
		return id;
	}

	/**
		Creates a new task in the `Created` state.
	**/
	public function new(parent:Null<AbstractTask>) {
		id = atomicId.add(1);
		this.parent = parent;
		state = new AtomicState(Created);
		error = new AtomicObject(null);
		cancellationManager = @:nullSafety(Off) new TaskCancellationManager(this);
		numActiveChildren = new AtomicInt(0);
		if (parent != null) {
			parent.addChild(this);
		}
	}

	/**
		Returns the task's error value if it has completed with one, or `null` otherwise.
	**/
	public function getError() {
		// The state is the authority: `error` can be set on a task that completes successfully
		// anyway, or is still cancelling, and in neither case is it the task's outcome.
		return state.load() == Cancelled ? error.load() : null;
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
		Requests cancellation of this task with `error` as its cause.

		The state is the authority on whether the task is cancelling. `error` is only meaningful once the
		state says so, which is why it is set before any transition to a cancelling state, and why the
		first error wins.
	**/
	function doCancel(error:Exception) {
		this.error.compareExchange(null, error);
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
		@:nullSafety(Off) final error:Exception = error.load();
		cancellationManager.run();
		cancelChildren(error.orCancellationException());
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
		Called when the task's own work has failed with `error`. Unlike `doCancel`, this cannot be
		prevented, but if cancellation was requested before, the error of that request is kept.

		The caller is responsible for calling `checkCompletion` afterwards.
	**/
	final function ownWorkFails(error:Exception) {
		this.error.compareExchange(null, error);
		while (true) {
			final current = state.load();
			switch (current) {
				case Running | CancellationRequested:
					if (state.compareExchange(current, Cancelling) == current) {
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
		Starts executing this task. Has no effect if the task has already been started or has completed.
	**/
	function activate() {
		if (state.compareExchange(Created, Running) == Created) {
			// Check if parent is cancelling and attempt to cancel this task before starting.
			// If the task has NonCancellable context, doCancel() will return early and
			// the task stays Running, allowing it to start.
			if (parent != null && parent.isCancelling()) {
				cancel();
			}
			// Only start if the task wasn't successfully cancelled
			if (state.load() == Running) {
				doStart();
			} else if (state.compareExchange(CancellationRequested, Cancelling) == CancellationRequested) {
				// The task's own work never starts.
				checkCompletion();
			}
		}
	}

	/**
		Arranges for `activate` to be called where this task is supposed to run.

		Calling this more than once is harmless, because `activate` only starts a created task.
	**/
	abstract function dispatchStart():Void;

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
					child.dispatchStart();
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
		switch (lockChildren()) {
			case 0:
				numActiveChildren.store(0);
			case activeChildren:
				numActiveChildren.store(activeChildren);
				return;
		}

		switch (state.load()) {
			case Created | Running | CancellationRequested:
				// The task's own work has not finished yet.
			case Completing:
				// If this fails, the task was cancelled concurrently and whoever did that checks again.
				if (state.compareExchange(Completing, Completed) == Completing) {
					complete();
				}
			case Cancelling:
				if (state.compareExchange(Cancelling, Cancelled) == Cancelling) {
					complete();
				}
			case Completed | Cancelled:
		}
	}

	function setInternalException(reason:String) {
		error.store(new TaskException(reason));
		cancel();
	}

	abstract function doStart():Void;

	abstract function complete():Void;

	abstract function childrenCompleted():Void;

	/**
		Reports `error`, which a callback registered with this task threw, without unwinding
		through the task machinery.
	**/
	@:allow(hxcoro.task.TaskCancellationManager)
	@:allow(hxcoro.task.TaskContinuationManager)
	abstract function reportCallbackError(error:Exception):Void;

	abstract function childSucceeds(child:AbstractTask):Void;

	abstract function childErrors(child:AbstractTask, cause:Exception):Void;

	abstract function childCancels(child:AbstractTask, cause:CancellationException):Void;

	// called from child

	function childCompletes(child:AbstractTask, processResult:Bool) {
		if (processResult) {
			switch (child.state.load()) {
				case Completed:
					childSucceeds(child);
				case Cancelled:
					@:nullSafety(Off) final childError:Exception = child.getError();
					if (childError is CancellationException) {
						childCancels(child, cast childError);
					} else {
						childErrors(child, childError);
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
				childrenCompleted();
				numActiveChildren.store(0);
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
