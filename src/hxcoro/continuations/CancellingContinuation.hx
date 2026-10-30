package hxcoro.continuations;

import haxe.Exception;
import haxe.coro.SuspensionResult;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CancellationException;
import haxe.atomic.AtomicInt;
import hxcoro.concurrent.BackOff;

private enum abstract State(Int) to Int {
	final Active;
	final Resolved;
	final Completing;
	final Completed;
}

/**
	Continuation wrapper used by `Coro.suspendCancellable` that resumes the wrapped
	continuation with a `CancellationException` if cancellation is requested before
	it is resumed normally.
**/
class CancellingContinuation<T> extends StackFrameContinuation<T> implements ICancellationCallback implements IDispatchObject {
	final resumeState : AtomicInt;

	var handle : Null<ICancellationHandle>;

	/**
		Callback that is invoked if cancellation wins over a normal resumption. It is set
		before this continuation registers with the cancellation token, so `onCancellation`
		always sees it.
	**/
	var onCancellationRequested : Null<CancellationException->Void>;

	public function new(cont) {
		super(cont);
		this.resumeState = new AtomicInt(Active);
	}

	function setState(result:Null<T>, error:Null<Exception>) {
		this.result = result;
		this.error = error;
		this.state = error == null ? Returned : Thrown;
	}

	/**
		Returning `true` means that we did update the state, so result and error are set.
	**/
	function updateState(result:Null<T>, error:Null<Exception>) {
		return switch (resumeState.compareExchange(Active, Completing)) {
			case Active:
				// We're first, set for resolve
				setState(result, error);
				resumeState.store(Completed);
				true;
			case Resolved:
				// Already resolved: set & schedule
				// The CAS is here in case updateState gets called multiple times
				if (resumeState.compareExchange(Resolved, Completing) == Resolved) {
					setState(result, error);
					resumeState.store(Completed);
					context.dispatchOrCall(this);
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

	/**
		Resumes the wrapped continuation with `cause` unless it was already resumed.
	**/
	public function onCancellation(cause:CancellationException) {
		if (updateState(null, cause)) {
			final f = onCancellationRequested;
			if (f != null) {
				f(cause);
			}
			handle?.close();
		}
	}

	/**
		Must be called after the suspending function has run. Sets `onCancellationRequested`
		and only then registers with the cancellation token, so cancellation that happened
		earlier is observed now. Returns `SuspensionResult.suspended` if this continuation was
		not resumed or cancelled yet, otherwise returns itself in `Returned` or `Thrown` state.
	**/
	public function resolve(onCancellationRequested:Null<CancellationException->Void>):SuspensionResult<T> {
		this.onCancellationRequested = onCancellationRequested;
		final cancellationToken = context.get(CancellationToken);
		if (cancellationToken != null && resumeState.load() == Active) {
			// Calls onCancellation immediately if the token is already cancelled
			final handle = cancellationToken.onCancellationRequested(this);
			this.handle = handle;
			// A resume on another thread may have missed the handle, so close it ourselves
			if (handle != null && resumeState.load() != Active) {
				handle.close();
			}
		}
		if (resumeState.compareExchange(Active, Resolved) == Active) {
			return cast SuspensionResult.suspended;
		} else {
			while (resumeState.load() == Completing) {
				BackOff.backOff();
			}
			return this;
		}
	}

	public function onDispatch() {
		cont.resume(result, error);
	}
}
