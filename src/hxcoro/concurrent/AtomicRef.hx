package hxcoro.concurrent;

import haxe.atomic.AtomicObject;

/**
	An atomic reference to a value of any reference type, including enum values.

	`haxe.atomic.AtomicObject` only accepts class instances (`T:{}`). This wrapper lifts that
	restriction by storing the value as `Dynamic`, which the underlying implementations compare
	by reference anyway. It is temporary: once https://github.com/HaxeFoundation/haxe/pull/13136
	is addressed, its uses become `AtomicObject` again.
**/
abstract AtomicRef<T>(AtomicObject<Dynamic>) {
	public inline function new(value:T) {
		this = new AtomicObject<Dynamic>(value);
	}

	/**
		Atomically replaces the value with `replacement` if it is `expected`, compared by reference,
		and returns the previous value.
	**/
	public inline function compareExchange(expected:T, replacement:T):T {
		return cast this.compareExchange(expected, replacement);
	}

	/**
		Atomically replaces the value with `value` and returns the previous value.
	**/
	public inline function exchange(value:T):T {
		return cast this.exchange(value);
	}

	/**
		Atomically reads the value.
	**/
	public inline function load():T {
		return cast this.load();
	}

	/**
		Atomically stores `value` and returns it.
	**/
	public inline function store(value:T):T {
		return cast this.store(value);
	}
}
