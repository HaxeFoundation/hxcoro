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
		The task's own work has finished with a result and it is waiting for its children to complete.
	**/
	final Completing;

	/**
		The task and all its children have completed successfully. This is a final state.
	**/
	final Completed;

	/**
		The task's own work has failed or been cancelled and it is waiting for its children to complete.
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
		`null` if the task has no error, otherwise its error as a `CancellationException`.
	**/
	public var cancellationException(get, never):Null<CancellationException>;

	// children

	final numActiveChildren:AtomicInt;
	var firstChild:Null<AbstractTask>;
	var nextSibling:Null<AbstractTask>;
	var previousSibling:Null<AbstractTask>;

	function get_cancellationException() {
		return switch (error.load()) {
			case null: null;
			case error: error.orCancellationException();
		}
	}

	public inline function get_id() {
		return id;
	}

	/**
		Creates a new task.
	**/
	public function new(parent:Null<AbstractTask>, initialState:TaskState) {
		id = atomicId.add(1);
		this.parent = parent;
		state = new AtomicState(Created);
		error = new AtomicObject(null);
		cancellationManager = @:nullSafety(Off) new TaskCancellationManager(this);
		numActiveChildren = new AtomicInt(0);
		if (parent != null) {
			parent.addChild(this);
		}
		switch (initialState) {
			case Created:
			case Running:
				activate();
			case _:
				setInternalException('Invalid initial state $initialState');
		}
	}

	/**
		Returns the task's error value, if any.
	**/
	public function getError() {
		return error.load();
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

	function doCancel(error:Exception) {
		if (this.error.compareExchange(null, error) != null) {
			// Already done
			checkCompletion();
			return;
		}
		final cause = error.orCancellationException();
		cancellationManager.run();
		final cause = new CancellationException();
		#if !js
		cause.stack = error.stack;
		#end
		cancelChildren(cause);
		checkCompletion();
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
		Returns `true` if the task has an error, i.e. cancellation has been requested or the task has failed.
		This remains `true` after the task has completed.
	**/
	public function isCancelling() {
		return error.load() != null;
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
			// isCancelling() will still be false, allowing the task to start.
			if (parent != null && parent.isCancelling()) {
				cancel();
			}
			// Only start if the task wasn't successfully cancelled
			if (!isCancelling()) {
				doStart();
			} else if (state.compareExchange(Running, Cancelling) == Running) {
				// If the task started but was already cancelling, transition to Cancelling state.
				checkCompletion();
			}
		}
	}

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
					child.activate();
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
			case Created:
				if (state.compareExchange(Created, Cancelled) == Created) {
					complete();
				}
			case Running:
				// Definitely not yet completed.
			case Completing if (isCancelling()):
				if (state.compareExchange(Completing, Cancelled) == Completing) {
					complete();
				}
			case Completing:
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
