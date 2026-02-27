package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.ISchedulerHandle;

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