package hxcoro.concurrent;

abstract AtomicState<T:Int>(AtomicInt) {
	public inline function new(state:T) {
		this = new AtomicInt(state);
	}

	public inline function change(expected:T, replacement:T) {
		return this.compareExchange(expected, replacement) == expected;
	}

	public inline function exchange(replacement:T):T {
		return cast this.exchange(replacement);
	}

	public inline function load():T {
		return cast this.load();
	}

	public inline function store(value:T) {
		this.store(value);
	}
}