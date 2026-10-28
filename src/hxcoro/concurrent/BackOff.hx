package hxcoro.concurrent;

/**
	Helper for spin loops that wait for another thread to make progress.
**/
class BackOff {
	/**
		Briefly yields to other threads or reaches a GC safepoint, depending on the target.
	**/
	static public inline function backOff() {
		#if hl
		hl.Gc.safepoint();
		#elseif cpp
		cpp.vm.Gc.safePoint();
		#elseif eval
		eval.vm.NativeThread.yield();
		#elseif jvm
		// jvm seems to do best without anything here
		#elseif lua_vanilla
		// Sys.sleep is not available in -D lua-vanilla; busy-wait without yielding
		#elseif sys
		Sys.sleep(1 / 0xFFFFFFFFu32);
		#else
		// ?
		#end
	}
}