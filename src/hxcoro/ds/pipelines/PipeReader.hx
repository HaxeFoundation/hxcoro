package hxcoro.ds.pipelines;

import hxcoro.ds.pipelines.Pipe.State;

class PipeReader {
	final state : State;

	public function new(state : State) {
		this.state = state;
	}

	@:coroutine public function read() {
		//
	}

	@:coroutine public function readAtLeast(count:Int) {
		//
	}

	public function advance(consumed:Int, observed:Int) {
		//
	}
}