package hxcoro.ds.pipelines.pipe;

import sys.thread.Mutex;
import haxe.Unit;
import haxe.io.ArrayBufferView;
import haxe.coro.IContinuation;
import haxe.atomic.AtomicInt;
import hxcoro.ds.channels.Channel;

/**
	The state shared between a `PipeReader` and a `PipeWriter`.
**/
class State {
	/**
		The continuation of the writer suspended in `flush`, if any.
	**/
	public var suspendedWriter : Null<IContinuation<Unit>>;
	/**
		The channel which carries flushed chunks from the writer to the reader.
	**/
	public final channel : Channel<ArrayBufferView>;
	/**
		The number of bytes that have been flushed but not yet consumed.
	**/
	public final count : AtomicInt;
	/**
		See `PipeOptions.writerPauseThreshold`.
	**/
	public final writerPauseThreshold : Int;
	/**
		See `PipeOptions.writerResumeThreshold`.
	**/
	public final writerResumeThreshold : Int;
	/**
		Guards `suspendedWriter`.
	**/
	public final lock : Mutex;

	public function new(writerPauseThreshold : Int, writerResumeThreshold : Int) {
		this.writerPauseThreshold  = writerPauseThreshold;
		this.writerResumeThreshold = writerResumeThreshold;
		this.suspendedWriter       = null;
		this.channel               = Channel.createUnbounded({});
		this.count                 = new AtomicInt(0);
		this.lock                  = new Mutex();
	}
}