package hxcoro;

import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
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

private typedef SuspendCancellableFunc<T> = IContinuation<T> -> Null<(CancellationException -> Void)>;

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
		Like `scope`, but the new task uses `context` instead of the caller's context. `context`
		is usually obtained from the caller's node with `node.with(...)` or `node.without(...)`,
		which keeps the new task a child of the caller. This is how to run a block under another
		`Dispatcher`, with a `CoroName`, or inside a `NonCancellable` boundary.

		The caller waits for the block even if it is cancelled in the meantime, so a
		`NonCancellable` block runs its cleanup to completion.

		If `context` has another `Dispatcher` than the caller, the block is dispatched there and
		the caller resumes on its own dispatcher afterwards. Otherwise the block starts running
		right away, like `scope`.
	**/
	@:coroutine static public function scopeWith<T>(context:Context, lambda:NodeLambda<T>#if coro.stack_traces, ?startPos:haxe.PosInfos#end):T {
		return suspend(cont -> {
			final scope = new CoroTaskWithLambda(context, lambda, Sequential#if coro.stack_traces, startPos#end);
			if (context.get(Dispatcher) == cont.context.get(Dispatcher)) {
				scope.onDispatch();
			} else {
				scope.requestActivation();
			}
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
