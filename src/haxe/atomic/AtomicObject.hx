package haxe.atomic;

// Temporary copy of the standard library's AtomicObject without the `T` constraint, so
// that an enum with payloads can be stored in it. Enum values are reference types on every
// target, which is all the implementations need. Remove this file once the standard library
// accepts enums, see https://github.com/HaxeFoundation/haxe/pull/13136.
//
// The sections are the per-target `_std` overrides of the standard library, followed by its
// generic implementation.

#if cpp

@:include("hx/atomic/AtomicObject.hpp")
@:cpp.ManagedType({type: "AtomicObject", namespace: ["hx", "atomic"], flags: [StandardNaming]})
private extern class AtomicObjectImpl {
	function new(value:Dynamic);

	function load():Dynamic;
	function store(value:Dynamic):Dynamic;
	function exchange(value:Dynamic):Dynamic;
	function compareExchange(expected:Dynamic, replacement:Dynamic):Dynamic;
}

private typedef AtomicObjectData<T> = AtomicObjectImpl;

#if cppia
extern
#end
abstract AtomicObject<T>(AtomicObjectData<T>) {
	#if cppia
	public function new(value:T):Void;

	public function compareExchange(expected:T, replacement:T):T;

	public function exchange(value:T):T;

	public function load():T;

	public function store(value:T):T;
	#else
	public #if !scriptable inline #end function new(value:T):Void {
		this = new AtomicObjectImpl(value);
	}

	public #if !scriptable inline #end function compareExchange(expected:T, replacement:T):T {
		return this.compareExchange(expected, replacement);
	}

	public #if !scriptable inline #end function exchange(value:T):T {
		return this.exchange(value);
	}

	public #if !scriptable inline #end function load():T {
		return this.load();
	}

	public #if !scriptable inline #end function store(value:T):T {
		return this.store(value);
	}
	#end
}
#elseif hl

#if (hl_ver < version("1.13.0") && !doc_gen)
#error "Atomic operations require HL 1.13+"
#end
import hl.Atomics;

// use hl.NativeArray<Dynamic> instead of hl.NativeArray<T>
// so that the compiler doesn't get confused and emit hl.Ref.make(this.getRef())
private typedef AtomicObjectData<T> = hl.NativeArray<Dynamic>;

abstract AtomicObject<T>(AtomicObjectData<T>) {
	public inline function new(value:T):Void {
		this = new hl.NativeArray(1);
		this[0] = value;
	}

	public inline function compareExchange(expected:T, replacement:T):T {
		return Atomics.compareExchangePtr(this.getRef(), expected, replacement);
	}

	public inline function exchange(value:T):T {
		return Atomics.exchangePtr(this.getRef(), value);
	}

	public inline function load():T {
		return Atomics.loadPtr(this.getRef());
	}

	public inline function store(value:T):T {
		return Atomics.storePtr(this.getRef(), value);
	}
}
#elseif jvm

import java.util.concurrent.atomic.AtomicReference;

private typedef AtomicObjectData<T> = AtomicReference<T>;

abstract AtomicObject<T>(AtomicObjectData<T>) {
	public inline function new(value:T) {
		this = new AtomicReference(value);
	}

	public inline function compareExchange(expected:T, replacement:T):T {
		// Java's compareAndSet returns a boolean, so do a CAS loop to be able to return the original value without a potential race condition

		var original;
		var real_replacement;
		do {
			original = this.get();
			real_replacement = original == expected ? replacement : original;
		} while (!this.compareAndSet(original, real_replacement));
		return original;
	}

	public inline function exchange(value:T):T {
		return this.getAndSet(value);
	}

	public inline function load():T {
		return this.get();
	}

	public inline function store(value:T):T {
		this.set(value);
		return value;
	}
}
#elseif eval

private typedef AtomicObjectData<T> = Any;

extern abstract AtomicObject<T>(AtomicObjectData<T>) {
	public function new(value:T):Void;

	public function compareExchange(expected:T, replacement:T):T;

	public function exchange(value:T):T;

	public function load():T;

	public function store(value:T):T;
}
#else

#if target.threaded

import sys.thread.Mutex;

private class AtomicObjectValue<T> {
	public final mutex:Mutex;
	public var value:T;

	public function new(value:T) {
		this.value = value;
		mutex = new Mutex();
	}
}

private typedef AtomicObjectData<T> = AtomicObjectValue<T>;

/**
	Atomic object. Use with care, this does not magically make it thread-safe to mutate objects.
**/
abstract AtomicObject<T>(AtomicObjectData<T>) {
	public function new(value:T):Void {
		this = new AtomicObjectData(value);
	}

	/**
		Atomically compares the value of `a` with `expected` and replaces `a` with `replacement` if they are equal..
		Returns the original value of `a`.

		Note that comparison is done by reference, and not by value.
		While this is expected for most objects, this might give unexpected behaviour for strings.
	**/
	public function compareExchange(expected:T, replacement:T):T {
		this.mutex.acquire();
		final value = this.value;
		if (this.value == expected) {
			this.value = replacement;
		}
		this.mutex.release();
		return value;
	}

	/**
		Atomically exchanges `a` with `value`.
		Returns the original value of `a`.
	**/
	public function exchange(value:T):T {
		this.mutex.acquire();
		final current = this.value;
		this.value = value;
		this.mutex.release();
		return current;
	}

	/**
		Atomically fetches the value of `a`.
	**/
	public function load():T {
		return this.value;
	}

	/**
		Atomically stores `value` into `a`.
		Returns the value that has been stored.
	**/
	public function store(value:T):T {
		this.mutex.acquire();
		this.value = value;
		this.mutex.release();
		return value;
	}
}

#else

private class AtomicObjectValue<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}

private typedef AtomicObjectData<T> = AtomicObjectValue<T>;

/**
	Atomic object. Use with care, this does not magically make it thread-safe to mutate objects.
	Not supported on JavaScript.
**/
abstract AtomicObject<T>(AtomicObjectData<T>) {
	public function new(value:T):Void {
		this = new AtomicObjectData(value);
	}

	/**
		Atomically compares the value of `a` with `expected` and replaces `a` with `replacement` if they are equal..
		Returns the original value of `a`.

		Note that comparison is done by reference, and not by value.
		While this is expected for most objects, this might give unexpected behaviour for strings.
	**/
	public function compareExchange(expected:T, replacement:T):T {
		final value = this.value;
		if (this.value == expected) {
			this.value = replacement;
		}
		return value;
	}

	/**
		Atomically exchanges `a` with `value`.
		Returns the original value of `a`.
	**/
	public function exchange(value:T):T {
		final current = this.value;
		this.value = value;
		return current;
	}

	/**
		Atomically fetches the value of `a`.
	**/
	public function load():T {
		return this.value;
	}

	/**
		Atomically stores `value` into `a`.
		Returns the value that has been stored.
	**/
	public function store(value:T):T {
		this.value = value;
		return value;
	}
}

#end
#end
