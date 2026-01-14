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
			final out       = new Out();
			final hasWaiter = readWaiters.tryPop(out);

			lock.release();

			if (hasWaiter) {
				out.get().succeedAsync(true);
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
			return suspendCancellable(cont -> {
				final hostPage  = writeWaiters.push(cont);

				lock.release();

				cont.onCancellationRequested = _ -> {
					lock.with(() -> writeWaiters.remove(hostPage, cont));
				}
			});
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
			lock.acquire();
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
			lock.release();
		}
	}
}
