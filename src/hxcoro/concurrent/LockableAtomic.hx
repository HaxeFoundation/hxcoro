package hxcoro.concurrent;

import haxe.atomic.AtomicInt;

/**
	An atomic value that doubles as a spin lock. While a thread holds the lock, the stored value is
	`LOCKED`, and the real value is only known to that thread, which passes it back when it unlocks.

	`T` is `Int` or an enum abstract over `Int`. No real value may be negative, so that it cannot be
	mistaken for `LOCKED`.

	The lock is meant for critical sections of a few instructions. Waiting threads spin, so
	nothing that blocks, allocates or dispatches should run while it is held.
**/
abstract LockableAtomic<T:Int>(AtomicInt) {
	/**
		The value stored while the lock is held.
	**/
	public static inline final LOCKED = -1;

	public inline function new(value:T) {
		this = new AtomicInt(value);
	}

	/**
		Returns the current value, which is `LOCKED` while a thread holds the lock.
	**/
	public inline function load():T {
		return cast this.load();
	}

	/**
		Returns `true` if `value` is the `LOCKED` marker.
	**/
	public static inline function isLocked(value:Int):Bool {
		return value == LOCKED;
	}

	/**
		Spins until the lock is free, takes it and returns the value it was holding.
	**/
	public function lock():T {
		while (true) {
			final value = this.load();
			if (value != LOCKED && this.compareExchange(value, LOCKED) == value) {
				return cast value;
			}
			BackOff.backOff();
		}
	}

	/**
		Spins until the lock is free, then takes it and returns the value it was holding, unless that
		value is `terminal`, which is returned without taking the lock.
	**/
	public function lockUnless(terminal:T):T {
		while (true) {
			final value = this.load();
			if (value == terminal) {
				return terminal;
			}
			if (value != LOCKED && this.compareExchange(value, LOCKED) == value) {
				return cast value;
			}
			BackOff.backOff();
		}
	}

	/**
		Takes the lock if the value is `expected`, without spinning, and returns the value found. The
		lock was taken if that is `expected`.
	**/
	public inline function tryLock(expected:T):T {
		return cast this.compareExchange(expected, LOCKED);
	}

	/**
		Stores `value` and releases the lock. Only the thread that took the lock may call this.
	**/
	public inline function unlock(value:T):Void {
		this.store(value);
	}

	/**
		Replaces `expected` with `replacement` without taking the lock, and returns the value found. Both
		have to be real values, so that this neither takes nor releases the lock.
	**/
	public inline function compareExchange(expected:T, replacement:T):T {
		return cast this.compareExchange(expected, replacement);
	}
}
