package hxcoro;

import haxe.exceptions.CancellationException;
import hxcoro.continuations.RacingContinuation;
import hxcoro.continuations.CancellingContinuation;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.dispatchers.Dispatcher;
import haxe.exceptions.ArgumentException;
import hxcoro.task.NodeLambda;
import hxcoro.task.CoroTask;
import hxcoro.exceptions.TimeoutException;
import hxcoro.continuations.TimeoutContinuation;

private typedef SuspendCancellableFunc<T> = IContinuation<T> -> Null<(CancellationException -> Void)>;

class Coro {
	@:coroutine @:coroutine.transformed
	public static function suspend<T>(completion:IContinuation<T>, func:IContinuation<T>->Void):SuspensionResult<T> {
		var safe = new RacingContinuation(completion);
		func(safe);
		safe.resolve();
		return safe;
	}

	/**
	 * Suspends a coroutine which will be automatically resumed with a `haxe.exceptions.CancellationException` when cancelled.
	 * If `func` returns a callback, it is registered to be invoked on cancellation allowing the easy cleanup of resources.
	 */
	@:coroutine @:coroutine.transformed public static function suspendCancellable<T>(completion:IContinuation<T>, func:SuspendCancellableFunc<T>):SuspensionResult<T> {
		var safe = new CancellingContinuation(completion);
		final onCancellationRequested = func(safe);
		if (onCancellationRequested != null) {
			safe.onCancellationRequested = onCancellationRequested;
		}
		safe.resolve();
		return safe;
	}

	static function delayImpl<T>(ms:Int, cont:IContinuation<T>) {
		final dispatcher = cont.context.getOrRaise(Dispatcher);
		final handle = dispatcher.scheduler.schedule(ms, cont);

		return _ -> {
			handle.close();
		}
	}

	@:coroutine @:coroutine.nothrow public static function delay(ms:Int):Void {
		suspendCancellable(cont -> delayImpl(ms, cont));
	}

	@:coroutine @:coroutine.nothrow public static function yield():Void {
		suspendCancellable(cont -> delayImpl(0, cont));
	}

	@:coroutine static public function scope<T>(lambda:NodeLambda<T>):T {
		return suspend(cont -> {
			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, CoroTask.CoroScopeStrategy);
			scope.awaitContinuation(cont);
		});
	}

	/**
		Executes `lambda` in a new task, ignoring all child exceptions.

		The task itself can still raise an exception. This is also true when calling
		`child.await()` on a child that raises an exception.
	**/
	@:coroutine static public function supervisor<T>(lambda:NodeLambda<T>):T {
		return suspend(cont -> {
			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, CoroTask.CoroSupervisorStrategy);
			scope.awaitContinuation(cont);
		});
	}

	/**
	 * Runs the provided lambda with a timeout, if the timeout is exceeded this functions throws `hxcoro.exceptions.TimeoutException`.
	 * If a timeout of zero is provided the function immediately throws `hxcoro.exceptions.TimeoutException`.
	 * @param ms Timeout in milliseconds.
	 * @param lambda Lambda function to execute.
	 * @throws `hxcoro.exceptions.TimeoutException` If the timeout is exceeded.
	 * @throws `haxe.ArgumentException` If the `ms` parameter is less than zero.
	 */
	@:coroutine public static function timeout<T>(ms:Int, lambda:NodeLambda<T>):T {
		if (ms < 0) {
			throw new ArgumentException('timeout must be positive');
		}
		if (ms == 0) {
			throw new TimeoutException();
		}

		return suspend(cont -> {

			final context = cont.context;
			final scope = new CoroTaskWithLambda(context, lambda, CoroTask.CoroScopeStrategy);
			final handle = context.scheduleFunction(ms, () -> {
				scope.cancel(new TimeoutException());
			});

			scope.awaitContinuation(new TimeoutContinuation(cont, handle));
		});
	}
}
