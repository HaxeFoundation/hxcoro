package hxcoro.ds.channels.bounded;

import haxe.Exception;
import haxe.coro.IContinuation;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.exceptions.ChannelClosedException;
import hxcoro.ds.channels.bounded.AtomicChannelState;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

final class BoundedWriter<T> implements IChannelWriter<T> {
	final state : AtomicChannelState;

	final buffer : CircularBuffer<T>;

	final writeWaiters : PagedDeque<IContinuation<Bool>>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final behaviour : FullBehaviour<T>;

	public function new(buffer, writeWaiters, readWaiters, behaviour, state) {
		this.buffer        = buffer;
		this.writeWaiters  = writeWaiters;
		this.readWaiters   = readWaiters;
		this.behaviour     = behaviour;
		this.state         = state;
	}

	public function tryWrite(v:T):Bool {
		if (state.changeIf(Open, Locked) == false) {
			return false;
		}

		return if (buffer.tryPush(v)) {
			final out       = new Out();
			final hasWaiter = readWaiters.tryPop(out);

			state.store(Open);

			if (hasWaiter) {
				out.get().succeedAsync(true);
			}

			true;
		} else {
			state.store(Open);

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
					if (state.lock()) {
						if (buffer.tryPopHead(out)) {
							state.store(Open);

							f(out.get());
						} else {
							state.store(Open);

							throw new Exception('Failed to drop newest item');
						}
					} else {
						throw new ChannelClosedException();
					}
				}

				return;
			case DropOldest(f):
				final out = new Out();

				while (tryWrite(v) == false) {
					if (state.lock()) {
						if (buffer.tryPopTail(out)) {
							state.store(Open);

							f(out.get());
						} else {
							state.store(Open);

							throw new Exception('Failed to drop oldest item');
						}
					} else {
						throw new ChannelClosedException();
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
		if (false == state.lock()) {
			return false;
		}

		return if (buffer.wasFull()) {
			return suspendCancellable(cont -> {
				final hostPage  = writeWaiters.push(cont);

				state.store(Open);

				cont.onCancellationRequested = _ -> {
					if (state.lock()) {
						writeWaiters.remove(hostPage, cont);
					}
				}
			});
		} else {
			state.store(Open);

			true;
		}
	}

	public function close() {
		if (false == state.lock()) {
			return;
		}

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

		state.store(Closed);
	}
}
