package hxcoro.ds.pipelines;

import hxcoro.ds.pipelines.Pipe.State;

class PipeReader {
	final state : State;

	public function new(state : State) {
		this.state = state;
	}

	public function read() {
		//
	}
}