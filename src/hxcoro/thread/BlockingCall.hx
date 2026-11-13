package hxcoro.thread;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;

/**
	Runs a function on the blocking pool, then resumes the caller of `hxcoro.Coro.blocking` with its outcome.
**/
class BlockingCall<T> implements IDispatchObject implements IContinuation<Any> {
	public var context(get, never):Context;

	final cont:IContinuation<T>;
	final func:() -> T;
	var result:Null<T>;
	var error:Null<Exception>;

	public function new(cont:IContinuation<T>, func:() -> T) {
		this.cont = cont;
		this.func = func;
		result = null;
		error = null;
	}

	function get_context() {
		return cont.context;
	}

	// Runs on a thread of the blocking pool.
	public function onDispatch() {
		final token = context.get(CancellationToken);
		// A caller that was cancelled while the call was queued doesn't run the function at all.
		error = token?.cancellationException;
		if (error == null) {
			try {
				result = func();
			} catch (e:Exception) {
				error = e;
			}
			// The function can't be interrupted, so a cancellation in the meantime only shows now.
			final cancellation = token?.cancellationException;
			if (cancellation != null) {
				result = null;
				error = cancellation;
			}
		}
		// Dispatching to the caller's dispatcher from here would run the caller on this thread
		// if that is a `TrampolineDispatcher`. The scheduler hands it over to the caller's loop.
		context.getOrRaise(Dispatcher).scheduler.schedule(0, this);
	}

	// Called by the scheduler through the caller's dispatcher.
	public function resume(_:Any, _:Exception) {
		cont.resume(cast result, cast error);
	}
}
