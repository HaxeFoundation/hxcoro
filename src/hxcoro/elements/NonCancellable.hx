package hxcoro.elements;

import haxe.coro.context.Key;
import haxe.coro.context.IElement;

/**
	A context element that prevents tasks created in its context from being cancelled,
	including through cancellation of their parent.
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