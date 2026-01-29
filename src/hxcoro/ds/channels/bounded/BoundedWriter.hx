package hxcoro.ds.channels.bounded;

import haxe.Exception;
import haxe.coro.IContinuation;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.bounded.AtomicChannelState;
import hxcoro.ds.channels.exceptions.ChannelClosedException;
import hxcoro.ds.channels.exceptions.InvalidChannelStateException;

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
		if (state.compareExchange(Open, Locked) != Open) {
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
					switch state.lock() {
						case Open:
							if (buffer.tryPopHead(out)) {
								state.store(Open);

								f(out.get());
							} else {
								state.store(Open);

								throw new Exception('Failed to drop newest item');
							}
						case Locked:
							throw new InvalidChannelStateException();
						case rejected:
							state.store(rejected);

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
								state.store(Open);

								f(out.get());
							} else {
								state.store(Open);

								throw new Exception('Failed to drop oldest item');
							}
						case Locked:
							throw new InvalidChannelStateException();
						case rejected:
							state.store(rejected);

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
				state.store(Draining);

				return false;
			case Locked:
				throw new InvalidChannelStateException();
			case Open:
				return if (buffer.wasFull()) {
					return suspendCancellable(cont -> {
						final hostPage = writeWaiters.push(cont);

						state.store(Open);

						cont.onCancellationRequested = _ -> {
							switch state.lock() {
								case Closed, Locked:
									throw new InvalidChannelStateException();
								case previous:
									writeWaiters.remove(hostPage, cont);
									state.store(previous);
							}
						}
					});
				} else {
					state.store(Open);

					true;
				}
		}
	}

	public function close() {
		switch state.lock() {
			case Closed:
				return;
			case Draining:
				state.store(Draining);

				return;
			case Locked:
				throw new InvalidChannelStateException();
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

				state.store(if (buffer.wasEmpty()) Closed else Draining);
		}
	}
}
