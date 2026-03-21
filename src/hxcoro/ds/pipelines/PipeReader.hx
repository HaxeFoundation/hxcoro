package hxcoro.ds.pipelines;

import haxe.Unit;
import haxe.Exception;
import haxe.exceptions.ArgumentException;
import haxe.io.ArrayBufferView;
import hxcoro.ds.Out;
import hxcoro.ds.pipelines.Pipe.State;

using hxcoro.util.Convenience;

class PipeReader {
	final state : State;
	final readOut : Out<ArrayBufferView>;
	var outstanding : Null<ArrayBufferView>;
	var fullyObserved : Bool;

	public function new(state : State) {
		this.state         = state;
		this.readOut       = new Out();
		this.outstanding   = null;
		this.fullyObserved = false;
	}

	@:coroutine public function waitForRead() {
		// I'm not sure if we should have the following checks or not,
		// it seems to make sense in some cases but not others.

		// // There is remaining data and the user has not specified any of it as "observed"
		// if (outstanding != null && fullyObserved == false) {
		// 	return true;
		// }

		return state.channel.reader.waitForRead();
	}

	public function tryRead(out:Out<ArrayBufferView>):Bool {
		if (state.channel.reader.tryRead(readOut)) {
			final chunk = readOut.get();

			fullyObserved = false;

			out.set(
				if (outstanding == null) {
					outstanding = chunk;
				} else {
					final newTotalSize = outstanding.byteLength + chunk.byteLength;
					final newView      = new ArrayBufferView(newTotalSize);

					newView.buffer.blit(0, outstanding.buffer, outstanding.byteOffset, outstanding.byteLength);
					newView.buffer.blit(outstanding.byteLength, chunk.buffer, chunk.byteOffset, chunk.byteLength);

					outstanding = newView;
				});

			return true;
		}

		return if (outstanding != null && fullyObserved == false) {
			fullyObserved = false;

			out.set(outstanding);

			true;
		} else {
			false;
		}
	}

	public function tryReadAtLeast(bytes:Int, out:Out<ArrayBufferView>):Bool {
		if (state.channel.reader.tryRead(readOut)) {
			final chunk = readOut.get();

			fullyObserved = false;

			out.set(
				if (outstanding == null) {
					outstanding = chunk;
				} else {
					final newTotalSize = outstanding.byteLength + chunk.byteLength;
					final newView      = new ArrayBufferView(newTotalSize);

					newView.buffer.blit(0, outstanding.buffer, outstanding.byteOffset, outstanding.byteLength);
					newView.buffer.blit(outstanding.byteLength, chunk.buffer, chunk.byteOffset, chunk.byteLength);

					outstanding = newView;
				});

			return outstanding.byteLength >= bytes;
		}

		return if (outstanding != null && fullyObserved == false && outstanding.byteLength >= bytes) {
			fullyObserved = false;

			out.set(outstanding);

			true;
		} else {
			false;
		}
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

		state.lock.acquire();
		if (state.count.load() <= state.writerResumeThreshold) {
			state.suspendedWriter?.succeedAsync(Unit);
			state.suspendedWriter = null;
		}
		state.lock.release();
	}
}