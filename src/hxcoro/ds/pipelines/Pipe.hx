package hxcoro.ds.pipelines;

import hxcoro.ds.pipelines.pipe.State;
import hxcoro.ds.pipelines.pipe.PipeReader;
import hxcoro.ds.pipelines.pipe.PipeWriter;

typedef PipeOptions = {
	var ?writerPauseThreshold:Int;
	var ?writerResumeThreshold:Int;
}

class Pipe {
	public final reader : PipeReader;
	public final writer : PipeWriter;

	function new(reader, writer) {
		this.reader = reader;
		this.writer = writer;
	}

	public static function create(options:Null<PipeOptions> = null) {
		final state  = new State(options?.writerPauseThreshold ?? 1024, options?.writerResumeThreshold ?? 512);
		final reader = new PipeReader(state);
		final writer = new PipeWriter(state);

		return new Pipe(reader, writer);
	}
}