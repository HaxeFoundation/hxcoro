package hxcoro.util;

import haxe.coro.Mutex;
import haxe.coro.Coroutine;

final class MutexExtensions {
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