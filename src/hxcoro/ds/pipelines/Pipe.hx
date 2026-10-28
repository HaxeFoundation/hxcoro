package hxcoro.ds.pipelines;

import hxcoro.ds.pipelines.pipe.State;
import hxcoro.ds.pipelines.pipe.PipeReader;
import hxcoro.ds.pipelines.pipe.PipeWriter;

/**
	Options for creating a `Pipe`.
**/
typedef PipeOptions = {
	/**
		The amount of unconsumed bytes at which `flush` suspends the writer. A value of 0 or
		less disables this. Defaults to 1024.
	**/
	var ?writerPauseThreshold:Int;
	/**
		The amount of unconsumed bytes at or below which a suspended writer is resumed. Defaults
		to 512.
	**/
	var ?writerResumeThreshold:Int;
}

/**
	A byte stream between a writer and a reader, with backpressure on the writer.
**/
class Pipe {
	/**
		The reading end of this pipe.
	**/
	public final reader : IPipeReader;
	/**
		The writing end of this pipe.
	**/
	public final writer : IPipeWriter;

	function new(reader, writer) {
		this.reader = reader;
		this.writer = writer;
	}

	/**
		Creates a new pipe.
	**/
	public static function create(options:Null<PipeOptions> = null) {
		final state  = new State(options?.writerPauseThreshold ?? 1024, options?.writerResumeThreshold ?? 512);
		final reader = new PipeReader(state);
		final writer = new PipeWriter(state);

		return new Pipe(reader, writer);
	}
}