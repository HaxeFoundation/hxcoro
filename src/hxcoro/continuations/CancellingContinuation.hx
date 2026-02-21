package hxcoro.continuations;

import haxe.coro.SuspensionResult;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.concurrent.AtomicInt;
import hxcoro.concurrent.BackOff;
import haxe.coro.dispatchers.Dispatcher;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;

private enum abstract State(Int) to Int {
	final Active;
	final Resolved;
	final Completing;
	final Completed;
}

class CancellingContinuation<T> extends SuspensionResult<T> implements IContinuation<T> implements ICancellationCallback implements IDispatchObject {
	final resumeState : AtomicInt;

	final cont : IContinuation<T>;

	final handle : Null<ICancellationHandle>;

	final cancellationToken : Null<ICancellationToken>;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public var onCancellationRequested (default, set) : Null<CancellationException->Void>;

	function set_onCancellationRequested(f : CancellationException->Void) {
		return switch (cancellationToken?.cancellationException) {
			case null:
				if (null != onCancellationRequested) {
					throw new Exception("Callback already registered");
				}

				onCancellationRequested = f;
			case exc:
				f(exc);

				f;
		}
	}

	public function new(cont) {
		super(Pending);
		this.resumeState  = new AtomicInt(Active);
		this.cont   = cont;
		cancellationToken = cont.context.get(CancellationToken);
		if (cancellationToken != null) {
			this.handle = cancellationToken.onCancellationRequested(this);
		}
	}

	/**
		Returning `true` means that we did update the state, so result and error are set.
	**/
	function updateState(result:Null<T>, error:Null<Exception>) {
		return switch (resumeState.compareExchange(Active, Completing)) {
			case Active:
				// We're first, set for resolve
				this.result = result;
				this.error = error;
				resumeState.store(Completed);
				true;
			case Resolved:
				// Already resolved: set & schedule
				// The CAS is here in case updateState gets called multiple times
				if (resumeState.compareExchange(Resolved, Completing) == Resolved) {
					this.result = result;
					this.error = error;
					resumeState.store(Completed);
					context.getOrRaise(Dispatcher).dispatch(this);
					true;
				} else {
					false;
				}
			case Completing | Completed:
				// Already cancelled
				false;
			case _:
				// Invalid state
				false;
		}
	}

	public function resume(result:T, error:Exception) {
		if (updateState(result, error)) {
			handle?.close();
		}
	}

	public function onCancellation(cause:CancellationException) {
		if (updateState(null, cause)) {
			if (null != onCancellationRequested) {
				onCancellationRequested(cause);
			}
			handle?.close();
		}
	}

	public function resolve():Void {
		if (resumeState.compareExchange(Active, Resolved) == Active) {
			state = Pending;
		} else {
			while (resumeState.load() == Completing) {
				BackOff.backOff();
			}
			if (error != null) {
				state = Thrown;
			} else {
				state = Returned;
			}
		}
	}

	public function onDispatch() {
		cont.resume(result, error);
	}
}