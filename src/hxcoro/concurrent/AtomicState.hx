package hxcoro.concurrent;

/**
	A convenience type over `AtomicInt` to be used with an enum abstract
	over `Int`.
**/
abstract AtomicState<T:Int>(AtomicInt) {
	/**
		Creates a new atomic state with initial state `state`.
	**/
	public inline function new(state:T) {
		this = new AtomicInt(state);
	}

	/**
		Atomically updates the value to `replacement` if the current value is `expected`.
		Returns the current value.
	**/
	public inline function compareExchange(expected:T, replacement:T):T {
		return cast this.compareExchange(expected, replacement);
	}

	/**
		Atomically updates the value to `replacement` and returns the previous value.
	**/
	public inline function exchange(replacement:T):T {
		return cast this.exchange(replacement);
	}

	/**
		Returns the current value.
	**/
	public inline function load():T {
		return cast this.load();
	}

	/**
		Stores `value` as the current value.
	**/
	public inline function store(value:T) {
		this.store(value);
	}
}