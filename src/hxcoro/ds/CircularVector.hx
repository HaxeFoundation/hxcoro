package hxcoro.ds;

private typedef ActualStorage<T> =
#if hl
	hl.NativeArray<T>
#else
	haxe.ds.Vector<T>
#end;

abstract CircularVector<T>(ActualStorage<T>) {
	public var length(get, never):Int;

	public inline function new(vector:ActualStorage<T>) {
		this = vector;
	}

	public inline function get_length() {
		return this.length;
	}

	@:arrayAccess public inline function get(i:Int) {
		// `& (x - 1)` is the same as `% x` when x is a power of two
		return this[i & (this.length - 1)];
	}

	@:arrayAccess public inline function set(i:Int, v:T) {
		return this[i & (this.length - 1)] = v;
	}

	static public inline function create<T>(size:Int) {
		return new CircularVector<T>(@:nullSafety(Off) new ActualStorage(size));
	}
}
