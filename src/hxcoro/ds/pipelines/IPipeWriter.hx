package hxcoro.ds.pipelines;

import haxe.io.ArrayBufferView;

/**
	The writing end of a `Pipe`.

	Data is written by requesting a buffer with `getBuffer`, filling it, committing it with
	`advance` and sending all committed data to the reader with `flush`.
**/
interface IPipeWriter {
	/**
		Returns a new buffer of at least `minimumSize` bytes to write into. Throws an exception if
		the previous buffer has not been committed with `advance` yet.
	**/
	function getBuffer(minimumSize:Int=0):ArrayBufferView;
	/**
		Commits the first `count` bytes of the buffer returned by `getBuffer`. A `count` of 0
		discards the buffer.
	**/
	function advance(count:Int):Void;
	/**
		Sends all committed data to the reader. Suspends if the amount of unconsumed data reaches
		the pipe's `writerPauseThreshold`, until the reader consumes enough of it.
	**/
	@:coroutine function flush():Void;
	/**
		Signals that no more data will be written. Committed data that has not been flushed is
		not sent.
	**/
	function close():Void;
}