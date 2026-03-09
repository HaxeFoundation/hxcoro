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

class CancellingContinuation<T> extends StackFrameContinuation<T> implements ICancellationCallback implements IDispatchObject {
	final resumeState : AtomicInt;

	final handle : Null<ICancellationHandle>;

	final cancellationToken : Null<ICancellationToken>;

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
		super(cont);
		this.resumeState  = new AtomicInt(Active);
		cancellationToken = cont.context.get(CancellationToken);
		if (cancellationToken != null) {
			this.handle = cancellationToken.onCancellationRequested(this);
		}
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

	public function onCancellation(cause:CancellationException) {
		if (updateState(null, cause)) {
			if (null != onCancellationRequested) {
				onCancellationRequested(cause);
			}
			handle?.close();
		}
	}

	public function resolve():SuspensionResult<T> {
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