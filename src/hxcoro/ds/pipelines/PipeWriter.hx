package hxcoro.ds.pipelines;

import haxe.io.BytesBuffer;
import hxcoro.ds.pipelines.Pipe.State;
import haxe.Exception;
import haxe.exceptions.ArgumentException;
import haxe.io.Bytes;
import haxe.io.ArrayBufferView;

class PipeWriter {
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
			throw new Exception("");
		}

		final actualSize = if (minimumSize == 0) 1024 else minimumSize;

		return current = new ArrayBufferView(actualSize);
	}

	public function advance(count:Int) {
		if (count < 0) {
			throw new ArgumentException("count", "Count must be non negative");
		}

		switch current {
			case null:
				throw new Exception("");
			case _:
				if (count == 0) {
					return;
				}

				@:nullSafety(Off) pending.push(current.sub(0, count));

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