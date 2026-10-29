package hxcoro.ds.channels.unbounded;

import sys.thread.Mutex;
import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import hxcoro.ds.Out;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

using hxcoro.util.MutexExtensions;

private final class WaitContinuation<T> implements IContinuation<Bool> {
	final cont : IContinuation<Bool>;

	final buffer : PagedDeque<T>;

	final lock : Mutex;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public function new(cont, buffer, lock) {
		this.cont   = cont;
		this.buffer = buffer;
		this.lock   = lock;
	}

	public function resume(result:Null<Bool>, error:Null<Exception>) {
		final result = lock.with(() -> {
			return if (false == result) {
				// The channel was closed, but there might still be data left to read.
				buffer.isEmpty() == false;
			} else {
				true;
			}
		});

		cont.succeedAsync(result);
	}
}

/**
	The reader of a channel created by `Channel.createUnbounded`.
**/
final class UnboundedReader<T> implements IChannelReader<T> {
	final buffer : PagedDeque<T>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final closed : Out<Bool>;

	final lock : Mutex;

	public function new(buffer, readWaiters, closed, lock) {
		this.buffer      = buffer;
		this.readWaiters = readWaiters;
		this.closed      = closed;
		this.lock        = lock;
	}

	public function tryRead(out:Out<T>):Bool {
		return lock.with(() -> buffer.tryPop(out));
	}

	public function tryPeek(out:Out<T>):Bool {
		return lock.with(() -> buffer.tryPeek(out));
	}

	@:coroutine public function read():T {
		final out = new Out();

		while (true)
		{
			if (waitForRead() == false) {
				throw new ChannelClosedException();
			}

			if (tryRead(out)) {
				return out.get();
			}
		}
	}

	@:coroutine public function waitForRead():Bool {
		lock.acquire();

		if (buffer.isEmpty() == false) {
			lock.release();

			return true;
		}

		if (closed.get()) {
			lock.release();

			return false;
		}

		return suspendCancellable(cont -> {
			final obj       = new WaitContinuation(cont, buffer, lock);
			final hostPage  = readWaiters.push(obj);

			lock.release();

			_ -> {
				lock.with(() -> readWaiters.remove(hostPage, obj));
			}
		});
	}
}