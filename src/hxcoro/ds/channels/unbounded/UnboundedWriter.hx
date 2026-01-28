package hxcoro.ds.channels.unbounded;

import haxe.coro.Mutex;
import haxe.coro.IContinuation;
import hxcoro.Coro;
import hxcoro.ds.Out;
import hxcoro.ds.PagedDeque;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

final class UnboundedWriter<T> implements IChannelWriter<T> {
	final closed : Out<Bool>;

	final buffer : PagedDeque<T>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final lock : Mutex;

	public function new(buffer, readWaiters, closed, lock) {
		this.buffer      = buffer;
		this.readWaiters = readWaiters;
		this.closed      = closed;
		this.lock        = lock;
	}

	public function tryWrite(v:T):Bool {
		lock.acquire();

		if (closed.get()) {
			lock.release();

			return false;
		}

		buffer.push(v);

		final out       = new Out();
		final hasWaiter = readWaiters.tryPop(out);

		lock.release();

		if (hasWaiter) {
			out.get().succeedAsync(true);
		}

		return true;
	}

	@:coroutine public function waitForWrite():Bool {
		checkCancellation();

		if (lock.with(() -> closed.get())) {
			return false;
		}

		return true;
	}

	@:coroutine public function write(v:T) {
		while (waitForWrite()) {
			if (tryWrite(v)) {
				return;
			}
		}

		throw new ChannelClosedException();
	}

	public function close() {
		final justClosed = lock.with(() -> {
			if (closed.get()) {
				return false;
			}

			closed.set(true);

			return true;
		});

		if (justClosed) {
			// Should be safe to act on the read waiters without the lock at this point.
			// All other code which pushes read waiters should be checking closed first.
			final out = new Out();
			while (readWaiters.tryPop(out)) {
				out.get().succeedAsync(false);
			}
		}
	}

	@:coroutine function checkCancellation() {
		return Coro.suspendCancellable(cont -> {
			cont.succeedAsync(null);
		});
	}
}