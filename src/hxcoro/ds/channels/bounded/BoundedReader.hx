package hxcoro.ds.channels.bounded;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import hxcoro.ds.Out;
import hxcoro.ds.CircularBuffer;
import hxcoro.ds.channels.exceptions.ChannelClosedException;
import hxcoro.ds.channels.bounded.AtomicChannelState;

using hxcoro.util.Convenience;
using hxcoro.util.MutexExtensions;

private final class WaitContinuation<T> implements IContinuation<Bool> {
	final cont : IContinuation<Bool>;

	final buffer : CircularBuffer<T>;

	final state : AtomicChannelState;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public function new(cont, buffer, state) {
		this.cont   = cont;
		this.buffer = buffer;
		this.state  = state;
	}

	public function resume(result:Bool, error:Exception) {
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
		if (state.lock()) {
			return if (buffer.tryPopTail(out)) {
				final out       = new Out();
				final hasWaiter = writeWaiters.tryPop(out);

				state.store(Open);

				if (hasWaiter) {
					out.get().succeedAsync(true);
				}

				true;
			} else {
				state.store(Open);

				false;
			}
		} else {
			return buffer.tryPopTail(out);
		}

	}

	public function tryPeek(out:Out<T>):Bool {
		return if (state.lock()) {
			final result = buffer.tryPeekHead(out);

			state.store(Open);

			result;
		} else {
			false;
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
		if (state.lock() == false) {
			return buffer.wasEmpty() == false;
		}

		if (buffer.wasEmpty() == false) {
			state.store(Open);

			return true;
		}

		return suspendCancellable(cont -> {
			final obj       = new WaitContinuation(cont, buffer, state);
			final hostPage  = readWaiters.push(obj);

			state.store(Open);

			cont.onCancellationRequested = _ -> {
				if (state.lock()) {
					readWaiters.remove(hostPage, obj);
					state.store(Open);
				}
			}
		});
	}
}