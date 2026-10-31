import eval.luv.Signal;
import haxe.coro.IContinuation;
import hxcoro.Coro.*;

/**
	Receives a signal such as `SIGINT`, which Ctrl+C sends. While the listener is open, the
	signal doesn't have its default effect, such as ending the process.

	Like everything that uses libuv handles, this may only be used from coroutines running on a
	`LoopDispatcher`.
**/
class SignalListener {
	final signal:Signal;
	var pending = 0;
	var waiter:Null<IContinuation<Bool>>;
	var closed = false;

	function new(signal:Signal) {
		this.signal = signal;
	}

	/**
		Starts listening for `sigNum`.
	**/
	@:coroutine static public function listen(sigNum:SigNum) {
		final listener = new SignalListener(Signal.init(LoopDispatcher.currentLoop()).resolve());
		switch (listener.signal.start(sigNum, listener.onSignal)) {
			case Ok(_):
				return listener;
			case Error(e):
				listener.close();
				throw new eval.luv.LuvException(e);
		}
	}

	function onSignal() {
		final waiter = waiter;
		if (waiter != null) {
			this.waiter = null;
			waiter.resume(true, null);
		} else {
			pending++;
		}
	}

	/**
		Suspends until the signal is received. Signals that were received while nobody was waiting
		are returned right away, one per call.
	**/
	@:coroutine public function next() {
		if (pending > 0) {
			pending--;
			return;
		}
		suspendCancellable(cont -> {
			waiter = cont;
			_ -> {
				waiter = null;
			}
		});
	}

	/**
		Stops listening, so the signal has its default effect again. Cancel a pending `next` call
		before closing the listener.
	**/
	public function close() {
		if (!closed) {
			closed = true;
			signal.stop();
			signal.close(() -> {});
		}
	}
}
