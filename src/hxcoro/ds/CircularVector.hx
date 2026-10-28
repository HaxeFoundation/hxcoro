package hxcoro.ds;

private typedef ActualStorage<T> =
#if hl
	hl.NativeArray<T>
#else
	haxe.ds.Vector<T>
#end;

/**
	A fixed-size vector whose indices wrap around its length.

	The wrapping uses a bit mask, so the length must be a power of two.
**/
abstract CircularVector<T>(ActualStorage<T>) {
	/**
		The number of slots in the underlying storage.
	**/
	public var length(get, never):Int;

	public inline function new(vector:ActualStorage<T>) {
		this = vector;
	}

	public inline function get_length() {
		return this.length;
	}

	/**
		Returns the element at index `i` modulo `length`.
	**/
	@:arrayAccess public inline function get(i:Int) {
		// `& (x - 1)` is the same as `% x` when x is a power of two
		return this[i & (this.length - 1)];
	}

	/**
		Sets the element at index `i` modulo `length` to `v`.
	**/
	@:arrayAccess public inline function set(i:Int, v:T) {
		return this[i & (this.length - 1)] = v;
	}

	/**
		Creates a new `CircularVector` with `size` slots. `size` must be a power of two.
	**/
	static public inline function create<T>(size:Int) {
		return new CircularVector<T>(new ActualStorage(size));
	}
}
