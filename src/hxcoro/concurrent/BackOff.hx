package hxcoro.concurrent;

class BackOff {
	static public inline function backOff() {
		#if hl
		hl.Gc.safepoint();
		#elseif cpp
		cpp.vm.Gc.safePoint();
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