package hxcoro.ds.pipelines;

import haxe.io.BytesBuffer;
import haxe.coro.Mutex;
import haxe.coro.IContinuation;

class State {
	public var suspendedWriter : Null<IContinuation<Bool>>;
	public var suspendedReader : Null<IContinuation<Bool>>;
	public final lock : Mutex;
	public final buffer : BytesBuffer;

	public function new() {
		suspendedWriter = null;
		suspendedReader = null;
		lock            = new Mutex();
		buffer          = new BytesBuffer();
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