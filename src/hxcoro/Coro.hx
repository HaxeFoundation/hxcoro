package hxcoro;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.SuspensionResult;
import haxe.coro.dispatchers.Dispatcher;
import haxe.exceptions.ArgumentException;
import haxe.exceptions.CancellationException;
import hxcoro.continuations.CancellingContinuation;
import hxcoro.continuations.RacingContinuation;
import hxcoro.continuations.TimeoutContinuation;
import hxcoro.TimeoutException;
import hxcoro.task.CoroTask;
import hxcoro.task.TaskKind;
import hxcoro.task.NodeLambda;
#if target.threaded
import hxcoro.thread.BlockingPool;
#end

private typedef SuspendCancellableFunc<T> = IContinuation<T> -> Null<(CancellationException -> Void)>;

#if target.threaded
/**
	Runs a function on the blocking pool, then resumes the caller of `Coro.blocking` with its outcome.
**/
private class BlockingCall<T> implements IDispatchObject implements IContinuation<Any> {
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
#end

/**
	Core coroutine functions for suspending, delaying and structuring coroutine execution.
**/
class Coro {
	/**
		Suspends the current coroutine and calls `func` with a continuation that resumes it.

		The continuation may be resumed while `func` is still running or at any later point,
		including from another thread. If it is resumed before `func` returns, the coroutine
		continues synchronously without actually suspending. Cancellation does not resume the
		coroutine, see `suspendCancellable` for that.
	**/
	@:coroutine(transformed)
	public static function suspend<T>(completion:IContinuation<T>, func:IContinuation<T>->Void):SuspensionResult<T> {
		var safe = new RacingContinuation(completion);
		func(safe);
		return safe.resolve();
	}

	/**
		Like `suspend`, but cancellation also resumes the coroutine, which then throws a
		`haxe.exceptions.CancellationException`.

		If `func` returns a callback, it is invoked if the coroutine is cancelled while
		suspended, which allows cleaning up resources.
	**/
	@:coroutine(transformed)
	public static function suspendCancellable<T>(completion:IContinuation<T>, func:SuspendCancellableFunc<T>):SuspensionResult<T> {
		final safe = new CancellingContinuation(completion);
		return safe.resolve(func(safe));
	}

	static function delayImpl<T>(ms:Int, cont:IContinuation<T>) {
		final dispatcher = cont.context.getOrRaise(Dispatcher);
		final handle = dispatcher.scheduler.schedule(ms, cont);

		return _ -> {
			handle.close();
		}
	}

	/**
		Suspends the current coroutine for `ms` milliseconds, as measured by the scheduler of
		the context's `Dispatcher`.
	**/
	@:coroutine(assert = { numStates: 1})
	public static function delay(ms:Int):Void {
		suspendCancellable(cont -> delayImpl(ms, cont));
	}

	/**
		Suspends the current coroutine and schedules it to be resumed without delay, giving
		other pending work a chance to run. Equivalent to `delay(0)`.
	**/
	@:coroutine(assert = { numStates: 1})
	public static function yield():Void {
		suspendCancellable(cont -> delayImpl(0, cont));
	}

	/**
		Calls `func` on a thread of the context's `BlockingPool` and returns its result, or throws
		its exception, once it has returned. The coroutine is suspended in the meantime, so `func`
		may block without blocking the dispatcher.

		`func` is not interrupted if the coroutine is cancelled. The call still waits for it to
		return and then throws the `haxe.exceptions.CancellationException`. If the coroutine is
		cancelled before `func` has started, `func` is not called.

		On targets without threads, `func` is called directly and blocks the dispatcher.

		Throws `CoroutineException` if the context has no `BlockingPool`.
	**/
	@:coroutine public static function blocking<T>(func:() -> T):T {
		#if target.threaded
		return suspend(cont -> {
			cont.context.getOrRaise(BlockingPool).run(new BlockingCall(cont, func));
		});
		#else
		return func();
		#end
	}

	/**
		Executes `lambda` in a new `Sequential` task and returns its result once the task and all
		its children have completed. The task runs in place of the caller, which waits for it.

		If `lambda` or one of the children raises an exception, the remaining children are
		cancelled and the exception is thrown from this call.
	**/
	@:coroutine static public function scope<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):T {
		return suspend(cont -> {
			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, Sequential#if coro.stack_traces, startPos#end);
			// The scope has our context, so we already run on its dispatcher and can activate it ourselves.
			scope.onDispatch();
			scope.awaitContinuation(cont#if coro.stack_traces, startPos#end);
		});
	}

	/**
		Like `scope`, but the task is a `SequentialSupervisor`: exceptions raised by children are
		ignored, but calling `await` on such a child still throws its exception. If `lambda` raises
		an exception, the remaining children are cancelled and the exception is thrown from this call.
	**/
	@:coroutine static public function supervisor<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):T {
		return suspend(cont -> {
			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, SequentialSupervisor#if coro.stack_traces, startPos#end);
			scope.onDispatch();
			scope.awaitContinuation(cont#if coro.stack_traces, startPos#end);
		});
	}

	/**
		Like `scope`, executes `lambda` in a new task and returns its result once the task and
		all its children have completed. If this takes longer than `ms` milliseconds, the task
		is cancelled and a `hxcoro.TimeoutException` is thrown from this call.

		A timeout of 0 throws the `TimeoutException` immediately without running `lambda`,
		and a negative timeout throws a `haxe.exceptions.ArgumentException`.
	**/
	@:coroutine public static function timeout<T>(ms:Int, lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):T {
		if (ms < 0) {
			throw new ArgumentException('timeout must be positive');
		}
		final exception = new TimeoutException();
		if (ms == 0) {
			throw exception;
		}
		return suspend(cont -> {
			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, Sequential#if coro.stack_traces, startPos#end);
			scope.onDispatch();
			final handle = context.scheduleFunction(ms, () -> {
				#if coro.stack_traces
				context.setExceptionStack(cast cont, exception);
				#end
				scope.cancel(exception);
			});

			scope.awaitContinuation(new TimeoutContinuation(cont, handle));
		});
	}
}
