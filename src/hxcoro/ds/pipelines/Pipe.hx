package hxcoro.ds.pipelines;

import haxe.Unit;
import haxe.io.BytesBuffer;
import haxe.coro.Mutex;
import haxe.coro.IContinuation;

class State {
	public var suspendedWriter : Null<IContinuation<Unit>>;
	public var suspendedReader : Null<IContinuation<Unit>>;
	public final lock : Mutex;
	public final buffer : BytesBuffer;
	public final writerPauseThreshold : Int;
	public final writerResumeThreshold : Int;

	public function new() {
		suspendedWriter = null;
		suspendedReader = null;
		lock            = new Mutex();
		buffer          = new BytesBuffer();
		writerPauseThreshold  = 1024;
		writerResumeThreshold = 512;
	}
}

class Pipe {
	public final writer : PipeWriter;
	public final reader : PipeReader;

	public function new() {
		writer = new PipeWriter(null);
		reader = new PipeReader(null);
	}
}