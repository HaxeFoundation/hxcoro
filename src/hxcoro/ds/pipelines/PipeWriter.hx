package hxcoro.ds.pipelines;

import haxe.io.BytesBuffer;
import hxcoro.ds.pipelines.Pipe.State;
import haxe.Exception;
import haxe.exceptions.ArgumentException;
import haxe.io.Bytes;
import haxe.io.ArrayBufferView;

private class PendingData {
	var backing : Bytes;
	var cursor : Int;

	public function new(size:Int) {
		backing = Bytes.alloc(size);
		cursor  = 0;
	}

	public function get(size:Int) {
		if (backing.length - cursor < size) {
			final increased = Bytes.alloc(backing.length + size);

			increased.blit(0, backing, 0, backing.length);

			backing = increased;
		}

		return ArrayBufferView.fromBytes(backing, cursor, size);
	}

	public function advance(size:Int) {
		cursor += size;
	}

	public function commit(buffer:BytesBuffer) {
		buffer.addBytes(backing, 0, cursor);

		cursor = 0;
	}
}

class PipeWriter {
	final state : State;

	var pending : Null<PendingData>;
	var current : Null<ArrayBufferView>;

	public function new(state:State) {
		this.state   = state;
		this.pending = null;
		this.current = null;
	}

	public function getBuffer(minimumSize:Int = 0):ArrayBufferView {
		if (minimumSize < 0) {
			throw new ArgumentException("minimumSize", "Buffer size must be non negative");
		}

		if (current != null) {
			throw new Exception("");
		}

		final actualSize = if (minimumSize == 0) 1024 else minimumSize;

		if (pending == null) {
			pending = new PendingData(actualSize);
		}

		return current = pending.get(actualSize);
	}

	public function advance(count:Int) {
		if (count < 0) {
			throw new ArgumentException("count", "Count must be non negative");
		}

		switch current {
			case null:
				throw new Exception("");
			case _:
				current = null;

				pending.advance(count);
		}
	}

	public function flush() {
		state.lock.acquire();

		pending.commit(state.buffer);

		state.lock.release();

		// TODO : suspend when some backpressure metric is reached
	}

	public function close() {
		//
	}
}