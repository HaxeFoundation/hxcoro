package hxcoro.concurrent;

#if target.threaded
typedef Tls<T> = haxe.coro.Tls<T>;
#else
typedef Tls<T> = TlsImpl<T>;

private class TlsImpl<T> {
	public var value:Null<T>;

	public function new() {
		value = null;
	}
}
#end