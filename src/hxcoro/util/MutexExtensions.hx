package hxcoro.util;

import sys.thread.Mutex;
import haxe.coro.Coroutine;

/**
	Static extensions for `sys.thread.Mutex`.
**/
final class MutexExtensions {
	/**
		Calls `f` while holding `lock` and returns its result. The lock is released even if
		`f` throws.
	**/
	public static inline function with<T>(lock:Mutex, f:()->T) {
		lock.acquire();

		var result;
		try {
			result = f();
		} catch (exn:Any) {
			lock.release();
			throw exn;
		}

		lock.release();

		return result;
	}
}