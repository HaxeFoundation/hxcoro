package hxcoro.ds.channels.bounded;

import haxe.coro.Mutex;
import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

private final class WaitContinuation<T> implements IContinuation<Bool> {
	final cont : IContinuation<Bool>;

	final buffer : CircularBuffer<T>;

	final closed : Out<Bool>;

	final lock : Mutex;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public function new(cont, buffer, closed, lock) {
		this.cont   = cont;
		this.buffer = buffer;
		this.closed = closed;
		this.lock   = lock;
	}

	public function resume(result:Bool, error:Exception) {
		final result = lock.with(() -> {
			if (false == result) {
				// closed.set(false);

				buffer.wasEmpty();
			} else {
				true;
			}
		});

		cont.succeedAsync(result);
	}
}

final class BoundedReader<T> implements IChannelReader<T> {
	final buffer : CircularBuffer<T>;

	final writeWaiters : PagedDeque<IContinuation<Bool>>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final closed : Out<Bool>;

	final lock : Mutex;

	public function new(buffer, writeWaiters, readWaiters, closed, lock) {
		this.buffer        = buffer;
		this.writeWaiters  = writeWaiters;
		this.readWaiters   = readWaiters;
		this.closed        = closed;
		this.lock          = lock;
	}

	public function tryRead(out:Out<T>):Bool {
		lock.acquire();

		return if (buffer.tryPopTail(out)) {
			final out     = new Out();
			final waiters = [];

			// for (_ in 0...buffer.getCapacity()) {
				if (writeWaiters.tryPop(out)) {
					waiters.push(out.get());
				}
				// else {
					// break;
				// }
			// }

			lock.release();

			for (waiter in waiters) {
				waiter.succeedAsync(true);
			}

			true;
		} else {
			lock.release();

			false;
		}
	}

	public function tryPeek(out:Out<T>):Bool {
		return lock.with(() -> buffer.tryPeekHead(out));
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

		if (buffer.wasEmpty() == false) {
			lock.release();

			return true;
		}

		if (closed.get()) {
			lock.release();

			return false;
		}

		final result = suspendCancellable(cont -> {
			final obj       = new WaitContinuation(cont, buffer, closed, lock);
			final hostPage  = readWaiters.push(obj);

			lock.release();

			cont.onCancellationRequested = _ -> {
				lock.with(() -> readWaiters.remove(hostPage, obj));
			}
		});
		if (result) {
			final out = new Out();
			if (readWaiters.tryPop(out)) {
				out.get().succeedAsync(true);
			}
		}
		return result;
	}
}