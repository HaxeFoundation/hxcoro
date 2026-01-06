package hxcoro.ds.channels;

import haxe.coro.Mutex;
import haxe.coro.IContinuation;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.Out;
import hxcoro.ds.PagedDeque;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.bounded.BoundedReader;
import hxcoro.ds.channels.bounded.BoundedWriter;
import hxcoro.ds.channels.bounded.SingleBoundedReader;
import hxcoro.ds.channels.bounded.SingleBoundedWriter;
import hxcoro.ds.channels.unbounded.UnboundedReader;
import hxcoro.ds.channels.unbounded.UnboundedWriter;
import hxcoro.concurrent.AtomicObject;

typedef DropCallback<T> = (dropped : T)->Void;

enum FullBehaviour<T> {
	Wait;
	DropNewest(f : DropCallback<T>);
	DropOldest(f : DropCallback<T>);
	DropWrite(f : DropCallback<T>);
}

typedef ChannelOptions = {
	var ?singleReader : Bool;

	var ?singleWriter : Bool;
}

typedef BoundedChannelOptions<T> = ChannelOptions & {
	var size : Int;

	var ?writeBehaviour : FullBehaviour<T>;
}

class Channel<T> implements IChannelReader<T> implements IChannelWriter<T> {

	public final reader : IChannelReader<T>;

	public final writer : IChannelWriter<T>;

	public function new(reader, writer) {
		this.reader = reader;
		this.writer = writer;
	}

	public static function createBounded<T>(options : BoundedChannelOptions<T>):Channel<T> {
		if (options.size < 1) {
			throw new ArgumentException("size");
		}

		final closed         = new Out();
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
		final lock         = new Mutex();

		closed.set(false);

		return
			new Channel(
				new BoundedReader(buffer, writeWaiters, readWaiters, closed, lock),
				new BoundedWriter(buffer, writeWaiters, readWaiters, closed, writeBehaviour, lock));
	}

	public static function createUnbounded<T>(options : ChannelOptions):Channel<T> {
		final closed      = new Out();
		final buffer      = new PagedDeque();
		final readWaiters = new PagedDeque();
		final lock        = new Mutex();

		closed.set(false);

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
