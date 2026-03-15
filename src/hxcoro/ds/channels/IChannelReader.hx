package hxcoro.ds.channels;

import hxcoro.ds.Out;

@:using(hxcoro.ds.channels.IChannelReader.ChannelReaderTools)
interface IChannelReader<T> {
	function tryRead(out:Out<T>):Bool;

	function tryPeek(out:Out<T>):Bool;

	@:coroutine function read():T;

	@:coroutine function waitForRead():Bool;
}

/**
	A lightweight coroutine-compatible iterator over a channel reader.

	Unlike the `AsyncGenerator`-based iterator, this implementation avoids the
	per-item coroutine state-machine overhead. Buffered items are served by a
	direct `tryRead()` call with no suspension. `waitForRead()` is only called
	when the buffer is found to be empty, so the cost of a coroutine
	suspend/resume is amortised over an entire burst of buffered items rather
	than paid once per item.
**/
class ChannelIterator<T> {
	final reader:IChannelReader<T>;
	final out:Out<T>;

	public function new(reader:IChannelReader<T>) {
		this.reader = reader;
		this.out = new Out();
	}

	/**
		Returns `true` and stores the next value when one is available, `false`
		when the channel is closed and fully drained.

		Fast path: if data is already buffered, reads it via `tryRead()` without
		any suspension.  Slow path: suspends via `waitForRead()` only when the
		buffer is empty, then retries.
	**/
	@:coroutine public function hasNext():Bool {
		while (true) {
			if (reader.tryRead(out))
				return true;
			if (!reader.waitForRead())
				return false;
		}
	}

	/** Returns the value that was stored by the preceding `hasNext()` call. **/
	public function next():T {
		return out.get();
	}
}

class ChannelReaderTools {
	static public function iterator<T>(reader:IChannelReader<T>) {
		return new ChannelIterator(reader);
	}
}