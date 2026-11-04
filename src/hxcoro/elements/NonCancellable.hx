package hxcoro.elements;

import haxe.coro.context.Key;
import haxe.coro.context.IElement;

/**
	A context element that makes the tasks created with it a boundary against cancellation: such a
	task is not cancelled when its parent is cancelled, and `cancel()` on it has no effect. This is
	meant for cleanup that has to run to completion, e.g. in a task that is already cancelling.

	The boundary protects only the task that introduced the element. Tasks created inside it inherit
	the element, but are ordinary tasks that `cancel()`, `cancelChildren()` and `timeout` affect as
	usual. Adding a new `NonCancellable` element inside the boundary starts another boundary.

	Failures are not cancellation and are never prevented: a failing child fails the task, and the
	error reaches awaiters and the task's parent.
**/
class NonCancellable implements IElement<NonCancellable> {
	/**
		The key under which this element is stored in a `Context`.
	**/
	static public final key = new Key<NonCancellable>("NonCancellable");

	public function new() {}

	public function getKey() {
		return key;
	}
}