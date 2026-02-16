package hxcoro.generators;

import haxe.Exception;
import haxe.coro.CoroIntrinsics;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import hxcoro.concurrent.CoroSemaphore;
import hxcoro.ds.channels.exceptions.ChannelClosedException;

class AsyncGenerator<T> implements IContinuation<Any> {
	public var context(get, null):Context;

	final readGuard:CoroSemaphore;
	final writeGuard:CoroSemaphore;
	var closed:Bool;
	var nextValue:Null<T>;

	function new(context:Context, f:Coroutine<AsyncGenerator<T> -> Void>) {
		this.context = context;
		readGuard = new CoroSemaphore(0, 1);
		writeGuard = new CoroSemaphore(0, 1);
		closed = false;
		f(this, this);
	}

	function get_context() {
		return context;
	}

	@:coroutine public function hasNext() {
		writeGuard.acquire();
		readGuard.release();
		return !closed;
	}

	public function next() {
		return nextValue;
	}

	public function resume(result:Null<Any>, error:Null<Exception>) {
		closed = true;
		writeGuard.release();
	}

	@:coroutine public function yield(value:T) {
		if (closed) {
			throw new ChannelClosedException();
		}
		nextValue = value;
		writeGuard.release();
		readGuard.acquire();
	}

	@:coroutine static public function create<T>(f:Coroutine<AsyncGenerator<T> -> Void>) {
		final context = CoroIntrinsics.getContext();
		return new AsyncGenerator(context, f);
	}
}
