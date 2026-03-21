package hxcoro.ds.pipelines;

import haxe.atomic.AtomicInt;
import haxe.io.ArrayBufferView;
import haxe.Unit;
import haxe.coro.IContinuation;
import hxcoro.ds.channels.Channel;
import sys.thread.Mutex;

class State {
	public var suspendedWriter : Null<IContinuation<Unit>>;
	public final channel : Channel<ArrayBufferView>;
	public final count : AtomicInt;
	public final writerPauseThreshold : Int;
	public final writerResumeThreshold : Int;
	public final lock : Mutex;

	public function new() {
		suspendedWriter       = null;
		channel               = Channel.createUnbounded({});
		count                 = new AtomicInt(0);
		writerPauseThreshold  = 1024;
		writerResumeThreshold = 512;
		lock                  = new Mutex();
	}
}

class Pipe {
	public final writer : PipeWriter;
	public final reader : PipeReader;

	public function new() {
		final state = new State();
		writer = new PipeWriter(state);
		reader = new PipeReader(state);
	}
}