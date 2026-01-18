package hxcoro.task;

import hxcoro.concurrent.AtomicObject;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.AtomicInt;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.exceptions.CancellationException;
import haxe.Exception;

enum abstract TaskState(Int) to Int {
	final Created;
	final Running;
	final Completing;
	final Completed;
	final Cancelling;
	final Cancelled;
}

class TaskException extends Exception {}

private class CancellationHandle implements ICancellationHandle {
	final callback:ICancellationCallback;
	final task:AbstractTask;

	var closed:Bool;

	public function new(callback, task) {
		this.callback = callback;
		this.task = task;

		closed = false;
	}

	public function run() {
		if (closed) {
			return;
		}

		final error = task.getError();
		callback.onCancellation(error.orCancellationException());

		closed = true;
	}

	public function close() {
		if (closed) {
			return;
		}
		final all = @:privateAccess task.cancellationCallbacks;

		if (all != null) {
			if (all.length == 1 && all[0] == this) {
				all.resize(0);
			} else {
				all.remove(this);
			}
		}

		closed = true;
	}
}

private class NoOpCancellationHandle implements ICancellationHandle {
	public function new() {}

	public function close() {}
}

/**
	AbstractTask is the base class for tasks which manages its `TaskState` and children.

	Developer note: it should have no knowledge of any asynchronous behavior or anything related to coroutines,
	and should be kept in a state where it could even be moved outside the hxcoro package. Also, `state` should
	be treated like a truly private variable and only be modified from within this class.
**/
abstract class AbstractTask implements ICancellationToken {
	static final atomicId = new AtomicInt(1); // start with 1 so we can use 0 for "no task" situations
	static final noOpCancellationHandle = new NoOpCancellationHandle();

	final parent:AbstractTask;

	var cancellationCallbacks:Null<Array<CancellationHandle>>;
	var state:AtomicState<TaskState>;
	var error:Null<Exception>;

	public var id(get, null):Int;
	public var cancellationException(get, never):Null<CancellationException>;

	// children

	var numActiveChildren:AtomicInt;
	var firstChild:AtomicObject<Null<AbstractTask>>;
	var nextSibling:Null<AbstractTask>;

	inline function get_cancellationException() {
		return switch state.load() {
			case Cancelling | Cancelled:
				error.orCancellationException();
			case _:
				null;
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
		error = null;
		cancellationCallbacks = null;
		numActiveChildren = new AtomicInt(0);
		firstChild = new AtomicObject(null);
		if (parent != null) {
			parent.addChild(this);
		}
		switch (initialState) {
			case Created:
			case Running:
				start();
			case _:
				throw new TaskException('Invalid initial state $initialState');
		}
	}

	/**
		Returns the task's error value, if any/
	**/
	public function getError() {
		return error;
	}

	/**
		Initiates cancellation of this task and all its children.

		If `cause` is provided, it is set as this task's error value and used to cancel all children.

		If the task cannot be cancelled or has already been cancelled, this function only checks if the
		task has completed and initiates the appropriate behavior.
	**/
	public function cancel(?cause:CancellationException) {
		// Use Zeta-loop to make sure we don't miss a state change
		var currentState = state.load();
		while (true) {
			switch (currentState) {
				case Created | Running | Completing:
					final nextState = state.compareExchange(currentState, Cancelling);
					if (nextState == currentState) {
						// Update successful, so this is the first and only time we get here
						cause ??= new CancellationException();
						// This has to happen before the state update!
						error ??= cause;
						state.store(Cancelling);

						if (null != cancellationCallbacks) {
							for (h in cancellationCallbacks) {
								h.run();
							}
						}

						cancelChildren(cause);
						checkCompletion();
						break;
					} else {
						// Loop with current value to try again
						currentState = nextState;
					}
				case Cancelling | Cancelled | Completed:
					checkCompletion();
					break;
			}
		}
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

	public function onCancellationRequested(callback:ICancellationCallback):ICancellationHandle {
		return switch (state.load()) {
			case Cancelling | Cancelled:
				callback.onCancellation(error.orCancellationException());

				return noOpCancellationHandle;
			case _:
				final container = cancellationCallbacks ??= [];
				final handle = new CancellationHandle(callback, this);

				container.push(handle);

				handle;
		}
	}

	/**
		Starts executing this task. Has no effect if the task is already active or has completed.
	**/
	public final function start() {
		if (state.changeIf(Created, Running)) {
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

	final inline function beginCompleting(f:() -> Void) {
		if (state.changeIf(Running, Completing)) {
			f();
			startChildren();
		}
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

		// If we get here, our current children are complete, but the task itself might still
		// be doing something. Note that we cannot rely on state == Running because the task
		// might do something in state == Cancelling as well.
		if (isDoingSomething()) {
			return;
		}

		// We now try to update to Completed/Cancelled.
		var currentState = state.load();
		while (true) {
			final targetState = switch (currentState) {
				case Completing:
					Completed;
				case Cancelling:
					Cancelled;
				case Completed | Cancelled:
					// This can happen from the loop, ignore.
					return;
				case state:
					// We can't be in Created or Running because then the call to `isDoingSomething()`
					// above should have returned true.
					// TODO: check `wasResumed` management in CoroTask.
					throw new TaskException('Invalid state $state in checkCompletion');
			};
			final nextState = state.compareExchange(currentState, targetState);
			if (nextState == currentState) {
				// CAS success means we're 100% done.
				complete();
				break;
			} else {
				// This could happen on a change from Completing to Cancelling, so we loop.
				currentState = nextState;
			}
		}
	}

	/**
		Whether or not the task itself is doing something, unrelated to its children.
	**/
	abstract function isDoingSomething():Bool;

	abstract function doStart():Void;

	abstract function complete():Void;

	abstract function childrenCompleted():Void;

	abstract function childSucceeds(child:AbstractTask):Void;

	abstract function childErrors(child:AbstractTask, cause:Exception):Void;

	abstract function childCancels(child:AbstractTask, cause:CancellationException):Void;

	// called from child

	function childCompletes(child:AbstractTask, processResult:Bool) {
		numActiveChildren.sub(1);
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
					throw new TaskException('Invalid state $state in childCompletes');
			}
		}
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
		switch (state.load()) {
			case Cancelling:
				child.cancel();
			case state = Cancelled | Completed:
				throw new TaskException('Invalid state $state in addChild');
			case Created | Running | Completing:
		}
	}
}
