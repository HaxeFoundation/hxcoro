package hxcoro.schedulers;

import haxe.Int64;

/**
	Helpers for passing `Int64` delays to timer APIs that take an `Int`.
**/
class TimerDelay {
	/**
		The longest delay in milliseconds that fits into an `Int`.
	**/
	static public inline final MAX_MS = 0x7FFFFFFF;

	/**
		Returns `ms` clamped to the range `[0, MAX_MS]`.
	**/
	static public function clamp(ms:Int64):Int {
		return if (ms <= 0) 0 else if (ms > MAX_MS) MAX_MS else Int64.toInt(ms);
	}
}
