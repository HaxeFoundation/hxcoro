package hxcoro.task;

import hxcoro.concurrent.AtomicObject;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.AtomicInt;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationToken;
import haxe.exceptions.CancellationException;
import haxe.Exception;

@:using(AbstractTask.TaskStateTools)
enum abstract TaskState(Int) to Int {
	final Created;
	final Running;
	final Completing;
	final Completed;
	final Cancelling;
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

class TaskException extends Exception {}

/**
	AbstractTask is the base class for tasks which manages its `TaskState` and children.

	Developer note: it should have no knowledge of any asynchronous behavior or anything related to coroutines,
	and should be kept in a state where it could even be moved outside the hxcoro package. Also, `state` should
	be treated like a truly private variable and only be modified from within this class.
**/
abstract class AbstractTask implements ICancellationToken {
	static final atomicId = new AtomicInt(1); // start with 1 so we can use 0 for "no task" situations

	final parent:AbstractTask;

	final cancellationManager:TaskCancellationManager;
	final error:AtomicObject<Null<Exception>>;
	final state:AtomicState<TaskState>;

	public var id(get, null):Int;
	public var cancellationException(get, never):Null<CancellationException>;

	// children

	final numActiveChildren:AtomicInt;
	final firstChild:AtomicObject<Null<AbstractTask>>;
	var nextSibling:Null<AbstractTask>;

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
		cancellationManager = new TaskCancellationManager(this);
		numActiveChildren = new AtomicInt(0);
		firstChild = new AtomicObject(null);
		// The correct order of operations here is:
		// 1. Add child to parent
		// 2. Start the child, if needed
		// 3. Cancel the child if the parent is cancelled
		if (parent != null) {
			parent.addChild(this);
		}
		switch (initialState) {
			case Created:
			case Running:
				start();
			case _:
				setInternalException('Invalid initial state $initialState');
		}
		if (parent?.isCancelling()) {
			cancel();
		}
	}

	/**
		Returns the task's error value, if any/
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
		final cause:CancellationException =
			if (error is CancellationException) {
				cast error;
			} else {
				new CancellationException();
			}
		cancellationManager.run();
		cancelChildren();
		checkCompletion();
	}

	/**
		Returns `true` if the task is still active. Note that an task that was created but not started yet
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

	public function isCancelling() {
		return error.load() != null;
	}

	public function onCancellationRequested(callback:ICancellationCallback):ICancellationHandle {
		return cancellationManager.addCallback(callback);
	}

	/**
		Starts executing this task. Has no effect if the task is already active or has completed.
	**/
	public final function start() {
		if (state.compareExchange(Created, Running) == Created) {
			doStart();
		}
	}

	/**
		Cancels all current children of this task, using `cause` as the reason.

		This task itself is not cancelled and continues to run. Newly created children
		are also not affected by this.
	**/
	public function cancelChildren(?cause:CancellationException) {
		var child = firstChild.load();
		if (null == child) {
			return;
		}

		cause ??= new CancellationException();

		do {
			child.cancel(cause);
			child = child.nextSibling;
		} while(child != null);
	}

	function startChildren() {
		var child = firstChild.load();
		while (child != null) {
			child.start();
			child = child.nextSibling;
		}
	}

	final function checkCompletion() {
		if (numActiveChildren.load() != 0) {
			return;
		}
		// We THINK that our current children are complete, but we don't know yet
		// because another call to `addChild` could come in.
		final child = firstChild.load();
		if (child != null) {
			if (firstChild.compareExchange(child, null) == child) {
				// If we have a child and successfully CAS it to null, children are
				// definitely complete.
				childrenCompleted();
			} else {
				// A call to `addChild` came in, so children are not complete yet.
				return;
			}
		}

		var currentState = state.load();
		while (true) {
			switch (currentState) {
				case Created:
					setInternalException('Bad state Created in checkCompletion');
				case Running:
					// Definitely not yet completed.
					return;
				case Completing:
					if (isCancelling()) {
						currentState = Cancelling;
						// loop
					} else {
						currentState = state.compareExchange(Completing, Completed);
						if (currentState == Completing) {
							complete();
							return;
						} else {
							// loop
						}
					}
				case Cancelling:
					state.store(Cancelled);
					complete();
					return;
				case Completed | Cancelled:
					// This can happen from the loop, ignore.
					return;
			}
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
					final childError = child.getError();
					if (childError is CancellationException) {
						childCancels(child, cast childError);
					} else {
						childErrors(child, childError);
					}
				case state:
					return setInternalException('Invalid state $state in childCompletes');
			}
		}
		numActiveChildren.sub(1);
		checkCompletion();
	}

	public function iterateChildren(f:AbstractTask -> Void) {
		final firstChild = firstChild.load();
		if (firstChild == null) {
			return;
		} else if (firstChild.isActive()) {
			f(firstChild);
		}
		var prev = firstChild;
		var current = firstChild.nextSibling;

		while (current != null) {
			if (!current.isActive()) {
				prev.nextSibling = current.nextSibling;
			} else {
				f(current);
			}
			current = current.nextSibling;
		}
	}

	// single-threaded

	function addChild(child:AbstractTask) {
		child.nextSibling = firstChild.exchange(child);
		numActiveChildren.add(1);
	}
}
