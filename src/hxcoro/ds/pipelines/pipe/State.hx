package hxcoro.ds.pipelines.pipe;

import sys.thread.Mutex;
import haxe.Unit;
import haxe.io.ArrayBufferView;
import haxe.coro.IContinuation;
import haxe.atomic.AtomicInt;
import hxcoro.ds.channels.Channel;

class State {
	public var suspendedWriter : Null<IContinuation<Unit>>;
	public final channel : Channel<ArrayBufferView>;
	public final count : AtomicInt;
	public final writerPauseThreshold : Int;
	public final writerResumeThreshold : Int;
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