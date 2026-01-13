package hxcoro.task;

import haxe.coro.Mutex;
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

private class TaskException extends Exception {}

class ThreadSafeAccess<T> {
	var obj:T;
	var mutex:Mutex;

	public function new(obj:T) {
		this.obj = obj;
		mutex = new Mutex();
	}

	public function access<R>(f:T -> R) {
		mutex.acquire();
		final r = f(obj);
		mutex.release();
		return r;
	}

	public function exchange(replacement:T) {
		mutex.acquire();
		final current = obj;
		obj = replacement;
		return current;
	}
}

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

		all.access(all -> {
			if (all.length == 1 && all[0] == this) {
				all.resize(0);
			} else {
				all.remove(this);
			}
		});

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
	var childrenMutex:Mutex;

	var children:Null<Array<AbstractTask>>;
	var cancellationCallbacks:ThreadSafeAccess<Array<CancellationHandle>>;
	var state:AtomicState<TaskState>;
	var error:Null<Exception>;
	var numCompletedChildren:AtomicInt;
	var indexInParent:Int;
	var allChildrenCompleted:Bool;

	public var id(get, null):Int;
	public var cancellationException(get, never):Null<CancellationException>;

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
		children = null;
		childrenMutex = new Mutex();
		cancellationCallbacks = new ThreadSafeAccess([]);
		numCompletedChildren = new AtomicInt(0);
		indexInParent = -1;
		allChildrenCompleted = false;
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
		switch (state.load()) {
			case Cancelled | Completed:
				// final states, nothing to do
			case Cancelling:
				checkCompletion();
			case Created | Running | Completing:
				switch (state.exchange(Cancelling)) {
					case Created | Running | Completing:
						// expected, keep going
					case Cancelling:
						// someone else got here first, but the state is fine
						return;
					case value = Cancelled | Completed:
						// final states, revert
						state.store(value);
						return;
				}
				cause ??= new CancellationException();
				if (error == null) {
					error = cause;
				}

				cancellationCallbacks.access(a -> {
					for (h in a) {
						h.run();
					}
				});

				cancelChildren(cause);
				checkCompletion();
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
				final handle = cancellationCallbacks.access(container -> {
					final handle = new CancellationHandle(callback, this);
					container.push(handle);
					handle;
				});

				handle;
		}
	}

	/**
		Starts executing this task. Has no effect if the task is already active or has completed.
	**/
	public final function start() {
		if (state.change(Created, Running)) {
			doStart();
		}
	}

	public function cancelChildren(?cause:CancellationException) {
		childrenMutex.acquire();
		if (null == children || children.length == 0) {
			childrenMutex.release();
			return;
		}

		cause ??= new CancellationException();

		final childrenToCancel = [];
		for (child in children) {
			if (child != null) {
				childrenToCancel.push(child);
			}
		}
		childrenMutex.release();

		for (child in childrenToCancel) {
			child.cancel(cause);
		}
	}

	final inline function beginCompleting() {
		if (state.change(Running, Completing)) {
			startChildren();
		}
	}

	function startChildren() {
		childrenMutex.acquire();
		if (null == children) {
			childrenMutex.release();
			return;
		}

		final childrenToStart = [];
		for (child in children) {
			if (child == null) {
				continue;
			}
			childrenToStart.push(child);
		}
		childrenMutex.release();

		for (child in childrenToStart) {
			child.start();
		}
	}

	function checkCompletion() {
		updateChildrenCompletion();
		if (!allChildrenCompleted) {
			return;
		}
		if (state.change(Completing, Completed) || state.change(Cancelling, Cancelled)) {
			complete();
		}
	}

	function updateChildrenCompletion() {
		if (allChildrenCompleted) {
			return;
		}
		childrenMutex.acquire();
		if (children == null) {
			allChildrenCompleted = true;
			childrenCompleted();
		} else if (numCompletedChildren.load() == children.length) {
			allChildrenCompleted = true;
			childrenCompleted();
		}
		childrenMutex.release();
	}

	abstract function doStart():Void;

	abstract function complete():Void;

	abstract function childrenCompleted():Void;

	abstract function childSucceeds(child:AbstractTask):Void;

	abstract function childErrors(child:AbstractTask, cause:Exception):Void;

	abstract function childCancels(child:AbstractTask, cause:CancellationException):Void;

	// called from child

	function childCompletes(child:AbstractTask, processResult:Bool) {
		numCompletedChildren.add(1);
		if (processResult) {
			if (child.error != null) {
				if (child.error is CancellationException) {
					childCancels(child, cast child.error);
				} else {
					childErrors(child, child.error);
				}
			} else {
				childSucceeds(child);
			}
		}
		updateChildrenCompletion();
		checkCompletion();
		if (child.indexInParent >= 0) {
			children[child.indexInParent] = null;
		}
	}

	function addChild(child:AbstractTask) {
		childrenMutex.acquire();
		final container = children ??= [];
		final index = container.push(child);
		childrenMutex.release();
		child.indexInParent = index - 1;
	}
}
