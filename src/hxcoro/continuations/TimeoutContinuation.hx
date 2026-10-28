package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.ISchedulerHandle;

/**
	Continuation wrapper used by `Coro.timeout` that closes the timeout's scheduler
	handle before asynchronously resuming the wrapped continuation.
**/
class TimeoutContinuation<T> extends StackFrameContinuation<T> {
	final handle : ISchedulerHandle;

	public function new(cont, handle) {
		super(cont);
		this.handle = handle;
	}

	public function resume(value:T, error:Exception) {
		handle.close();

		cont.resumeAsync(value, error);
	}
}