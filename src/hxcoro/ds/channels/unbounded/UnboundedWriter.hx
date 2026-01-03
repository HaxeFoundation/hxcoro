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
		return lock.with(() -> {
			if (closed.get()) {
				return false;
			}
	
			final _ = buffer.push(v);
	
			final cont = new Out();
			while (readWaiters.tryPop(cont)) {
				cont.get().succeedAsync(true);
			}
	
			return true;
		});
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
		lock.with(() -> {
			if (closed.get()) {
				return 0;
			}

			closed.set(true);

			final cont = new Out();
			while (readWaiters.tryPop(cont)) {
				cont.get().succeedAsync(false);
			}

			return 0;
		});
	}

	@:coroutine function checkCancellation() {
		return Coro.suspendCancellable(cont -> {
			cont.succeedAsync(null);
		});
	}
}