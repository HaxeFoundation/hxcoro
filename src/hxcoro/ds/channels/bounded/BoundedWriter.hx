package hxcoro.ds.channels.bounded;

import haxe.coro.Mutex;
import haxe.Exception;
import haxe.coro.IContinuation;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

final class BoundedWriter<T> implements IChannelWriter<T> {
	final closed : Out<Bool>;

	final buffer : CircularBuffer<T>;

	final writeWaiters : PagedDeque<IContinuation<Bool>>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final behaviour : FullBehaviour<T>;

	final lock : Mutex;

	public function new(buffer, writeWaiters, readWaiters, closed, behaviour, lock) {
		this.buffer        = buffer;
		this.writeWaiters  = writeWaiters;
		this.readWaiters   = readWaiters;
		this.closed        = closed;
		this.behaviour     = behaviour;
		this.lock          = lock;
	}

	public function tryWrite(v:T):Bool {
		lock.acquire();

		if (closed.get()) {
			lock.release();

			return false;
		}

		return if (buffer.tryPush(v)) {
			final out     = new Out();
			final waiters = [];

			// for (_ in 0...buffer.getCapacity()) {
				if (readWaiters.tryPop(out)) {
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

	@:coroutine public function write(v:T) {
		if (tryWrite(v)) {
			return;
		}

		switch behaviour {
			case Wait:
				while (waitForWrite()) {
					if (tryWrite(v)) {
						return;
					}
				}
			case DropNewest(f):
				final out = new Out();

				while (tryWrite(v) == false) {
					if (lock.with(() -> buffer.tryPopHead(out))) {
						f(out.get());
					} else {
						throw new Exception('Failed to drop newest item');
					}
				}

				return;
			case DropOldest(f):
				final out = new Out();

				while (tryWrite(v) == false) {
					if (lock.with(() -> buffer.tryPopTail(out))) {
						f(out.get());
					} else {
						throw new Exception('Failed to drop oldest item');
					}
				}

				return;
			case DropWrite(f):
				f(v);

				return;
		}

		throw new ChannelClosedException();
	}

	@:coroutine public function waitForWrite():Bool {
		lock.acquire();

		if (closed.get()) {
			lock.release();

			return false;
		}

		return if (buffer.wasFull()) {
			final result = suspendCancellable(cont -> {
				final hostPage  = writeWaiters.push(cont);

				lock.release();

				cont.onCancellationRequested = _ -> {
					lock.with(() -> writeWaiters.remove(hostPage, cont));
				}
			});
			if (result) {
				final out = new Out();
				if (writeWaiters.tryPop(out)) {
					out.get().succeedAsync(true);
				}
			}
			return result;
		} else {
			lock.release();

			true;
		}
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

			while (writeWaiters.isEmpty() == false) {
				switch writeWaiters.pop() {
					case null:
						continue;
					case cont:
						cont.succeedAsync(false);
				}
			};

			while (readWaiters.isEmpty() == false) {
				switch (readWaiters.pop()) {
					case null:
						continue;
					case cont:
						cont.succeedAsync(false);
				}
			};
		}
	}
}
