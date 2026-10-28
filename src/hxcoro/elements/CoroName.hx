package hxcoro.elements;

import haxe.coro.context.Key;
import haxe.coro.context.IElement;

/**
	A context element that assigns a name to the coroutines running in its context. hxcoro
	itself does not interpret the name; it can be retrieved via `context.get(CoroName)`.
**/
class CoroName implements IElement<CoroName> {
	/**
		The key under which this element is stored in a `Context`.
	**/
	static public final key = new Key<CoroName>("Name");

	/**
		The name of the coroutine.
	**/
	public final name:String;

	public function new(name:String) {
		this.name = name;
	}

	public function getKey() {
		return key;
	}
}