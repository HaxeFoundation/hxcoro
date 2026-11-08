package hxcoro.ds.channels.bounded;

import haxe.Exception;
import haxe.coro.IContinuation;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.bounded.AtomicChannelState;
import hxcoro.ds.channels.ChannelClosedException;
import hxcoro.ds.channels.InvalidChannelStateException;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

/**
	The writer of a channel created by `Channel.createBounded`.
**/
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
		if (state.tryLock(Open) != Open) {
			return false;
		}

		return if (buffer.tryPush(v)) {
			final out       = new Out();
			final hasWaiter = readWaiters.tryPop(out);

			state.unlock(Open);

			if (hasWaiter) {
				out.get().succeedAsync(true);
			}

			true;
		} else {
			state.unlock(Open);

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
					switch state.lock() {
						case Open:
							if (buffer.tryPopHead(out)) {
								state.unlock(Open);

								f(out.get());
							} else {
								state.unlock(Open);

								throw new Exception('Failed to drop newest item');
							}
						case rejected:
							state.unlock(rejected);

							throw new ChannelClosedException();
					}
				}

				return;
			case DropOldest(f):
				final out = new Out();

				while (tryWrite(v) == false) {
					switch state.lock() {
						case Open:
							if (buffer.tryPopTail(out)) {
								state.unlock(Open);

								f(out.get());
							} else {
								state.unlock(Open);

								throw new Exception('Failed to drop oldest item');
							}
						case rejected:
							state.unlock(rejected);

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
		switch state.lock() {
			case Closed:
				return false;
			case Draining:
				state.unlock(Draining);

				return false;
			case Open:
				return if (buffer.wasFull()) {
					return suspendCancellable(cont -> {
						final hostPage = writeWaiters.push(cont);

						state.unlock(Open);

						_ -> {
							switch state.lock() {
								case Closed:
									throw new InvalidChannelStateException();
								case previous:
									writeWaiters.remove(hostPage, cont);
									state.unlock(previous);
							}
						}
					});
				} else {
					state.unlock(Open);

					true;
				}
		}
	}

	public function close() {
		switch state.lock() {
			case Closed:
				return;
			case Draining:
				state.unlock(Draining);

				return;
			case Open:
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

				state.unlock(if (buffer.wasEmpty()) Closed else Draining);
		}
	}
}
