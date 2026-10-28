package hxcoro.ds.channels;

import haxe.coro.IContinuation;
import sys.thread.Mutex;
import haxe.exceptions.ArgumentException;
import haxe.atomic.AtomicObject;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.Out;
import hxcoro.ds.PagedDeque;
import hxcoro.ds.channels.bounded.AtomicChannelState;
import hxcoro.ds.channels.bounded.BoundedReader;
import hxcoro.ds.channels.bounded.BoundedWriter;
import hxcoro.ds.channels.bounded.SingleBoundedReader;
import hxcoro.ds.channels.bounded.SingleBoundedWriter;
import hxcoro.ds.channels.unbounded.UnboundedReader;
import hxcoro.ds.channels.unbounded.UnboundedWriter;
import hxcoro.generators.AsyncGenerator;

/**
	A callback which receives an item that was dropped by a full channel.
**/
typedef DropCallback<T> = (dropped : T)->Void;

/**
	Determines what `write` does when a bounded channel is full.
**/
enum FullBehaviour<T> {
	/**
		Suspend until there is space in the channel.
	**/
	Wait;
	/**
		Remove the most recently written item to make space, passing it to `f`.
	**/
	DropNewest(f : DropCallback<T>);
	/**
		Remove the oldest item to make space, passing it to `f`.
	**/
	DropOldest(f : DropCallback<T>);
	/**
		Discard the item being written, passing it to `f`.
	**/
	DropWrite(f : DropCallback<T>);
}

/**
	Options for creating a channel.
**/
typedef ChannelOptions = {
	/**
		Hint that the channel has only one reader. Currently ignored.
	**/
	var ?singleReader : Bool;

	/**
		Hint that the channel has only one writer. Currently ignored.
	**/
	var ?singleWriter : Bool;
}

/**
	Options for creating a bounded channel.
**/
typedef BoundedChannelOptions<T> = ChannelOptions & {
	/**
		The maximum number of items the channel can hold. Must be at least 1.
	**/
	var size : Int;

	/**
		What `write` does when the channel is full. Defaults to `Wait`.
	**/
	var ?writeBehaviour : FullBehaviour<T>;
}

/**
	A thread-safe queue for passing values between coroutines.

	A channel combines a `reader` and a `writer`, and itself forwards to both. After
	`close` is called, no more items can be written, but items already in the channel
	can still be read.
**/
class Channel<T> implements IChannelReader<T> implements IChannelWriter<T> {

	/**
		The reading end of this channel.
	**/
	public final reader : IChannelReader<T>;

	/**
		The writing end of this channel.
	**/
	public final writer : IChannelWriter<T>;

	public function new(reader, writer) {
		this.reader = reader;
		this.writer = writer;
	}

	/**
		Creates a channel which holds at most `options.size` items.

		Throws `haxe.exceptions.ArgumentException` if `options.size` is less than 1.
	**/
	public static function createBounded<T>(options : BoundedChannelOptions<T>):Channel<T> {
		if (options.size < 1) {
			throw new ArgumentException("size");
		}

		final writeBehaviour = options.writeBehaviour ?? Wait;

		// TODO : Revisit this single consumer producer implementation once we have threading in and can make some comparisons.
		// final singleReader   = options.singleReader ?? false;
		// final singleWriter   = options.singleWriter ?? false;
		// if (singleReader && singleWriter && writeBehaviour.match(DropNewest(_)) == false && writeBehaviour.match(DropOldest(_)) == false) {
		// 	final buffer      = new ConcurrentCircularBuffer(options.size);
		// 	final readWaiter  = new AtomicObject<IContinuation<Bool>>(null);
		// 	final writeWaiter = new AtomicObject<IContinuation<Bool>>(null);

		// 	return
		// 		new BoundedChannel(
		// 			new SingleBoundedReader(buffer, writeWaiter, readWaiter, closed),
		// 			new SingleBoundedWriter(buffer, writeWaiter, readWaiter, closed, writeBehaviour));
		// }

		final buffer       = new CircularBuffer(options.size);
		final readWaiters  = new PagedDeque();
		final writeWaiters = new PagedDeque();
		final state        = new AtomicChannelState();

		return
			new Channel(
				new BoundedReader(buffer, writeWaiters, readWaiters, state),
				new BoundedWriter(buffer, writeWaiters, readWaiters, writeBehaviour, state));
	}

	/**
		Creates a channel without a size limit, so writing never suspends.
	**/
	public static function createUnbounded<T>(options : ChannelOptions):Channel<T> {
		final closed      = new Out();
		final buffer      = new PagedDeque();
		final readWaiters = new PagedDeque();
		final lock        = new Mutex();

		return
			new Channel(
				new UnboundedReader(buffer, readWaiters, closed, lock),
				new UnboundedWriter(buffer, readWaiters, closed, lock));
	}

	public function tryRead(out:Out<T>):Bool {
		return reader.tryRead(out);
	}

	public function tryPeek(out:Out<T>):Bool {
		return reader.tryPeek(out);
	}

	@:coroutine public function read():T {
		return reader.read();
	}

	@:coroutine public function waitForRead():Bool {
		return reader.waitForRead();
	}

	public function tryWrite(out:T):Bool {
		return writer.tryWrite(out);
	}

	@:coroutine public function write(v:T) {
		return writer.write(v);
	}

	@:coroutine public function waitForWrite():Bool {
		return writer.waitForWrite();
	}

	public function close() {
		writer.close();
	}
}
