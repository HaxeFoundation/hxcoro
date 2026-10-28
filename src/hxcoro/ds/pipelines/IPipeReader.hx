package hxcoro.ds.pipelines;

import haxe.io.ArrayBufferView;

/**
	The reading end of a `Pipe`.

	Data that has been read stays available until it is consumed via `advance`.
**/
interface IPipeReader {
	/**
		Suspends until new data is available or the writer is closed. Returns `false` if the
		writer is closed and no more data will arrive.
	**/
	@:coroutine function waitForRead():Bool;
	/**
		Stores the available data in `out` without suspending, including data from earlier reads
		that was not consumed. Returns `false` if there is no data, or if all remaining data was
		marked as observed and nothing new has arrived.
	**/
	function tryRead(out:Out<ArrayBufferView>):Bool;
	/**
		Like `tryRead`, but returns `true` only if at least `count` bytes are available.
		Throws `haxe.exceptions.ArgumentException` if `count` is not positive.
	**/
	function tryReadAtLeast(count:Int, out:Out<ArrayBufferView>):Bool;
	/**
		Marks the first `consumed` bytes of the last read data as consumed, and the following
		`observed` bytes as examined but not consumed. Unconsumed data is returned again by the
		next read. Consuming data can resume a writer that is suspended in `flush`.
	**/
	function advance(consumed:Int, observed:Int):Void;
}