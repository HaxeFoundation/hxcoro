package hxcoro.ds.pipelines;

import haxe.Unit;
import haxe.io.Bytes;
import haxe.coro.Mutex;
import haxe.coro.IContinuation;

class State {
	public var suspendedWriter : Null<IContinuation<Unit>>;
	public var suspendedReader : Null<IContinuation<Unit>>;
	public var buffer : Null<Bytes>;
	public final lock : Mutex;
	public final writerPauseThreshold : Int;
	public final writerResumeThreshold : Int;

	public function new() {
		suspendedWriter = null;
		suspendedReader = null;
		lock            = new Mutex();
		buffer          = null;
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