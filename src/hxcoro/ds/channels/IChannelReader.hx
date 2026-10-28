package hxcoro.ds.channels;

import hxcoro.ds.Out;

/**
	The reading end of a channel.

	A reader can be iterated over in a coroutine, which yields items until the channel
	is closed and empty.
**/
@:using(hxcoro.ds.channels.IChannelReader.ChannelReaderTools)
interface IChannelReader<T> {
	/**
		Removes the next item and stores it in `out` without suspending. Returns `false` if
		no item is available.
	**/
	function tryRead(out:Out<T>):Bool;

	/**
		Stores the most recently written item in `out` without removing it. Returns `false` if
		no item is available.
	**/
	function tryPeek(out:Out<T>):Bool;

	/**
		Removes and returns the next item, suspending until one is available. Throws
		`hxcoro.ds.channels.exceptions.ChannelClosedException` if the channel is closed and empty.
	**/
	@:coroutine function read():T;

	/**
		Suspends until an item is available or the channel is closed. Returns `false` if
		the channel is closed and no more items can be read.

		A `true` result does not guarantee that a subsequent `tryRead` succeeds, since
		another reader may take the item first.
	**/
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

/**
	Static extensions for `IChannelReader`.
**/
class ChannelReaderTools {
	/**
		Returns a coroutine iterator over the items of `reader`.
	**/
	static public function iterator<T>(reader:IChannelReader<T>) {
		return new ChannelIterator(reader);
	}
}