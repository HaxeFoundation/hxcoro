package hxcoro.elements;

import haxe.coro.context.Key;
import haxe.coro.context.IElement;

class NonCancellable implements IElement<NonCancellable> {
	static public final key = new Key<NonCancellable>("NonCancellable");

	public function new() {}

	public function getKey() {
		return key;
	}
}