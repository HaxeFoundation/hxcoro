package hxcoro.concurrent;

class BackOff {
	static public inline function backOff() {
		#if hl
		hl.Gc.blocking(true);
		hl.Gc.blocking(false);
		#elseif cpp
		untyped __cpp__("__hxcpp_gc_safe_point()");
		#elseif eval
		eval.vm.NativeThread.yield();
		#elseif jvm
		// jvm seems to do best without anything here
		#elseif sys
		Sys.sleep(1 / 0xFFFFFFFFu32);
		#else
		// ?
		#end
	}
}