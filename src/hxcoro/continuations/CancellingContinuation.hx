package hxcoro.continuations;

import haxe.coro.SuspensionResult;
import haxe.coro.schedulers.IScheduleObject;
import hxcoro.concurrent.AtomicInt;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import haxe.coro.IContinuation;
import haxe.coro.ICancellableContinuation;
import haxe.coro.context.Context;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;

private enum abstract State(Int) to Int {
	final Active;
	final Resolved;
	final Completing;
	final Completed;
}

class CancellingContinuation<T> extends SuspensionResult<T> implements ICancellableContinuation<T> implements ICancellationCallback implements IScheduleObject {
	final resumeState : AtomicInt;

	final cont : IContinuation<T>;

	final handle : ICancellationHandle;

	public var context (get, never) : Context;

	function get_context() {
		return cont.context;
	}

	public var onCancellationRequested (default, set) : CancellationException->Void;

	function set_onCancellationRequested(f : CancellationException->Void) {
		return switch (cont.context.get(CancellationToken).cancellationException) {
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
		this.handle = this.cont.context.get(CancellationToken).onCancellationRequested(this);
	}

	/**
		Returning `true` means that we did update the state, so result and error are set.
	**/
	function updateState(result:T, error:Exception) {
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
					context.get(Scheduler).scheduleObject(this);
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
			handle.close();
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
				// Wait until the values are set
				#if eval
				eval.vm.NativeThread.yield();
				#end
			}
			if (error != null) {
				state = Thrown;
			} else {
				state = Returned;
			}
		}
	}

	public function onSchedule() {
		cont.resume(result, error);
	}
}