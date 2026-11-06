import haxe.Int64;
import haxe.coro.CoroIntrinsics;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.Dispatcher;
import hxcoro.Coro.*;
import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.run.Setup.LoopSetup;
import hxcoro.schedulers.HeapScheduler;
import hxcoro.schedulers.ILoop;
import sys.net.Socket;

enum abstract SocketEvent(Int) {
	/**
		The socket has data to read, has reached the end of its input, or has a connection to accept.
	**/
	final Readable;

	/**
		The socket can take more data to write.
	**/
	final Writable;
}

private class SocketWait {
	public final socket:Socket;
	public final event:SocketEvent;
	public final cont:IContinuation<Bool>;

	public function new(socket:Socket, event:SocketEvent, cont:IContinuation<Bool>) {
		this.socket = socket;
		this.event = event;
		this.cont = cont;
	}
}

/**
	A scheduler that also waits for sockets, using `sys.net.Socket.select`.

	Each `loop` iteration runs the timers that are due, then waits in `select` until a socket is
	ready or the next timer is due, and resumes the coroutines waiting for the sockets that are
	ready. Combined with a `TrampolineDispatcher`, everything runs on the thread that drives the
	loop.
**/
class SelectScheduler extends HeapScheduler implements ILoop {
	/**
		The longest time in seconds that `loop` waits, so that it notices timers scheduled from other
		threads.
	**/
	static inline final maxWait = 0.1;

	final waits:Array<SocketWait> = [];

	/**
		Suspends until `socket` is ready for `event`, and returns `true`. Returns `false` if waiting
		for `socket` was aborted by `abort`.
	**/
	@:coroutine public function wait(socket:Socket, event:SocketEvent):Bool {
		return suspendCancellable(cont -> {
			final wait = new SocketWait(socket, event, cont);
			waits.push(wait);
			_ -> {
				waits.remove(wait);
			}
		});
	}

	/**
		Makes the coroutines waiting for `socket` return `false` from `wait`. This must be called
		before closing a socket, because `select` fails for closed sockets.
	**/
	public function abort(socket:Socket) {
		for (wait in waits.copy()) {
			if (wait.socket == socket) {
				waits.remove(wait);
				wait.cont.resume(false, null);
			}
		}
	}

	public function loop(runMode:RunMode) {
		while (true) {
			var progress = runDueEvents();
			final timeout = progress || runMode == NoWait ? 0.0 : timeUntilNextEvent();
			progress = poll(timeout) || progress;
			if (progress || runMode == NoWait || runDueEvents()) {
				return;
			}
		}
	}

	/**
		Has no effect, because `loop` waits for `maxWait` at most.
	**/
	public function wakeUp() {}

	function eventScheduled() {}

	function runDueEvents() {
		final currentTime = now();
		var didSomething = false;
		while (true) {
			futureMutex.acquire();
			final minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				futureMutex.release();
				return didSomething;
			}
			heap.extract();
			futureMutex.release();
			didSomething = true;
			minimum.dispatch();
		}
	}

	function timeUntilNextEvent() {
		futureMutex.acquire();
		final minimum = heap.minimum();
		futureMutex.release();
		if (minimum == null) {
			return maxWait;
		}
		final ms = Int64.toInt(minimum.runTime - now());
		return Math.max(0, Math.min(maxWait, ms / 1000));
	}

	/**
		Waits up to `timeout` seconds for sockets to become ready, and resumes the coroutines waiting
		for them. Returns `true` if any were resumed.
	**/
	function poll(timeout:Float) {
		if (waits.length == 0) {
			// Windows' select fails without sockets.
			if (timeout > 0) {
				Sys.sleep(timeout);
			}
			return false;
		}
		final read = [for (wait in waits) if (wait.event == Readable) wait.socket];
		final write = [for (wait in waits) if (wait.event == Writable) wait.socket];
		final result = Socket.select(read, write, [], timeout);
		final ready = [
			for (wait in waits)
				if ((wait.event == Readable ? result.read : result.write).contains(wait.socket)) wait
		];
		for (wait in ready) {
			// Coroutines resumed before might have aborted this wait.
			if (waits.remove(wait)) {
				wait.cont.resume(true, null);
			}
		}
		return ready.length > 0;
	}

	/**
		Creates a setup that uses a `SelectScheduler` with a `TrampolineDispatcher`.
	**/
	static public function createSetup() {
		final scheduler = new SelectScheduler();
		return new LoopSetup(scheduler, new TrampolineDispatcher(scheduler));
	}

	/**
		Returns the scheduler of the current coroutine's dispatcher, which has to be a
		`SelectScheduler`.
	**/
	@:coroutine static public function current():SelectScheduler {
		final scheduler = CoroIntrinsics.getContext().getOrRaise(Dispatcher).scheduler;
		if (scheduler is SelectScheduler) {
			return cast scheduler;
		}
		throw 'Expected a SelectScheduler, got $scheduler';
	}
}
