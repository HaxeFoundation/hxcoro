package hxcoro.ds.pipelines.pipe;

import haxe.Exception;
import haxe.io.ArrayBufferView;
import haxe.exceptions.ArgumentException;

class PipeWriter implements IPipeWriter {
	final state : State;

	var current : Null<ArrayBufferView>;
	var pending : Array<ArrayBufferView>;

	public function new(state:State) {
		this.state   = state;
		this.current = null;
		this.pending = [];
	}

	public function getBuffer(minimumSize:Int = 0):ArrayBufferView {
		if (minimumSize < 0) {
			throw new ArgumentException("minimumSize", "Buffer size must be non negative");
		}

		if (current != null) {
			throw new Exception("Attempting to call getBuffer before calling advancing an existing buffer");
		}

		final actualSize = if (minimumSize == 0) 1024 else minimumSize;

		return current = new ArrayBufferView(actualSize);
	}

	public function advance(count:Int) {
		if (current == null) {
			throw new Exception("Attempting to advance before getBuffer has been called");
		}
		if (count < 0) {
			throw new ArgumentException("count", "Count must be non negative");
		}
		if (count == 0) {
			current = null;

			return;
		}

		@:nullSafety(Off) {
			if (count > current.byteLength) {
				throw new ArgumentException("count", "Count greater than the buffer size");
			}

			pending.push(current.sub(0, count));

			current = null;
		}
	}

	@:coroutine public function flush():Void {
		for (chunk in pending) {
			state.count.add(chunk.byteLength);
			state.channel.writer.write(chunk);
		}

		pending.resize(0);

		state.lock.acquire();

		if (state.writerPauseThreshold > 0 && state.count.load() >= state.writerPauseThreshold) {
			suspendCancellable(cont -> {
				state.suspendedWriter = cont;

				state.lock.release();

				_ -> {
					state.lock.acquire();
					state.suspendedWriter = null;
					state.lock.release();
				}
			});
		} else {
			state.lock.release();
		}
	}

	public function close() {
		state.channel.writer.close();
	}
}