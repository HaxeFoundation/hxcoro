package hxcoro.ds;

private abstract OutData<T>(Array<T>) from Array<T> {
	public inline function new() {
		this = [];
	}

	public inline function set(v:T):Void {
		this[0] = v;
	}

	public inline function get() {
		return this[0];
	}
}

/**
	A mutable container for a single value.
**/
abstract Out<T>(OutData<T>) {
	public inline function new() {
		this = new OutData();
	}

	/**
		Returns the stored value.
	**/
	public inline function get() {
		return this.get();
	}

	/**
		Stores `v`, replacing any previous value.
	**/
	public inline function set(v:T) {
		this.set(v);
	}
}