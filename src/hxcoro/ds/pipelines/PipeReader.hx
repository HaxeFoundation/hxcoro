package hxcoro.ds.pipelines;

import haxe.Exception;
import haxe.exceptions.ArgumentException;
import haxe.io.ArrayBufferView;
import hxcoro.ds.pipelines.Pipe.State;

class PipeReader {
	final state : State;
	var outstanding : Null<ArrayBufferView>;
	var fullyObserved : Bool;

	public function new(state : State) {
		this.state         = state;
		this.outstanding   = null;
		this.fullyObserved = false;
	}

	@:coroutine public function read() {
		// There is remaining data and the user has not specified any of it as "observed"
		if (outstanding != null && fullyObserved == false) {
			return outstanding;
		}

		final chunk = state.channel.reader.read();

		fullyObserved = false;

		return if (outstanding == null) {
			outstanding = chunk;
		} else {
			final newTotalSize = outstanding.byteLength + chunk.byteLength;
			final newView      = new ArrayBufferView(newTotalSize);

			newView.buffer.blit(0, outstanding.buffer, outstanding.byteOffset, outstanding.byteLength);
			newView.buffer.blit(outstanding.byteLength, chunk.buffer, chunk.byteOffset, chunk.byteLength);

			outstanding = newView;
		}
	}

	@:coroutine public function readAtLeast(count:Int) {
		//
	}

	public function advance(consumed:Int, observed:Int) {
		if (outstanding == null) {
			throw new Exception("");
		}
		if (consumed < 0 || consumed > outstanding.byteLength) {
			throw new ArgumentException("consumed");
		}
		if (observed < 0 || consumed + observed > outstanding.byteLength) {
			throw new ArgumentException("observed");
		}

		if (consumed == outstanding.byteLength) {
			outstanding = null;
		} else {
			outstanding   = outstanding.sub(consumed);
			fullyObserved = outstanding.byteLength == observed;
		}

		state.count.add(-consumed);
	}
}