package hxcoro.ds.channels.bounded;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.exceptions.ChannelClosedException;
import hxcoro.ds.channels.exceptions.InvalidChannelStateException;
import hxcoro.ds.channels.bounded.AtomicChannelState;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

private final class WaitContinuation<T> implements IContinuation<Bool> {
	final cont : IContinuation<Bool>;

	final buffer : CircularBuffer<T>;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public function new(cont, buffer) {
		this.cont   = cont;
		this.buffer = buffer;
	}

	public function resume(result:Null<Bool>, error:Null<Exception>) {
		final result = if (false == result) {
			buffer.wasEmpty();
		} else {
			true;
		}

		cont.succeedAsync(result);
	}
}

final class BoundedReader<T> implements IChannelReader<T> {
	final buffer : CircularBuffer<T>;

	final writeWaiters : PagedDeque<IContinuation<Bool>>;

	final readWaiters : PagedDeque<IContinuation<Bool>>;

	final state : AtomicChannelState;

	public function new(buffer, writeWaiters, readWaiters, state) {
		this.buffer        = buffer;
		this.writeWaiters  = writeWaiters;
		this.readWaiters   = readWaiters;
		this.state         = state;
	}

	public function tryRead(out:Out<T>):Bool {
		switch state.lock() {
			case Closed:
				return false;
			case Locked:
				throw new InvalidChannelStateException();
			case previous:
				final result = buffer.tryPopTail(out);

				return if (previous == Draining) {
					// In draining mode the channel does not accept any more data,
					// so if we just read the last remaining data we want to transition
					// to closed instead of draining.
					state.store(if (buffer.wasEmpty()) Closed else Draining);

					result;
				} else if (result) {
					// Only try and wake up a writer if our pop succeeded,
					// otherwise we might be waking up a write for no reason.
					final out       = new Out();
					final hasWaiter = writeWaiters.tryPop(out);

					state.store(Open);

					if (hasWaiter) {
						out.get().succeedAsync(true);
					}

					result;
				} else {
					state.store(Open);

					result;
				}
		}
	}

	public function tryPeek(out:Out<T>):Bool {
		return switch state.lock() {
			case Closed:
				false;
			case Locked:
				throw new InvalidChannelStateException();
			case previous:
				final result = buffer.tryPeekHead(out);

				state.store(previous);

				result;
		}
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
		switch state.lock() {
			case Closed:
				return false;
			case Locked:
				throw new InvalidChannelStateException();
			case Draining:
				// In draining mode there is always data in the buffer,
				// which is why it's safe to blindly return true.
				state.store(Draining);

				return true;
			case Open:
				if (buffer.wasEmpty() == false) {
					state.store(Open);

					return true;
				}

				return suspendCancellable(cont -> {
					final obj       = new WaitContinuation(cont, buffer);
					final hostPage  = readWaiters.push(obj);

					state.store(Open);

					_ -> {
						switch state.lock() {
							case Closed, Locked:
								throw new InvalidChannelStateException();
							case previous:
								readWaiters.remove(hostPage, obj);
								state.store(previous);
						}
					}
				});
		}
	}
}