package hxcoro.schedulers;

import haxe.coro.dispatchers.Dispatcher;
import hxcoro.concurrent.AtomicState;
import eval.luv.Async;
import haxe.atomic.AtomicInt;
import sys.thread.Deque;
import haxe.Int64;
import haxe.coro.IContinuation;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.coro.dispatchers.IDispatchObject;
import eval.luv.Timer;
import eval.luv.Loop;

enum abstract AsyncDequeState(Int) to Int {
	final Open;
	final Sending;
	final Closed;
}

class AsyncDeque<T> {
	final deque:Deque<T>;
	var async:Null<Async>;
	var state:AtomicState<AsyncDequeState>;

	public function new(loop:Loop, f:Async -> Void) {
		this.deque = new Deque<T>();
		this.async = Async.init(loop, f).resolve();
		state = new AtomicState(Open);
	}

	public function add(x:T) {
		while (true) {
			switch (state.compareExchange(Open, Sending)) {
				case Open:
					deque.add(x);
					async.send();
					state.store(Open);
					break;
				case Sending:
					// loop
				case Closed:
					// If we're already closed we must be in LuvScheduler.shutdown. We
					// can't use async anymore, but we can still add to the deque so the
					// shutdown can drain it.
					deque.add(x);
					return;
			}
		}
	}

	public function pop(block:Bool) {
		return deque.pop(block);
	}

	public function close() {
		async.close(() -> { });
	}
}

private enum abstract LuvTimerEventState(Int) to Int {
	final Created;
	final Started;
	final Cancelled;
	final Stopped;
}

private class LuvTimerEvent implements ISchedulerHandle implements IDispatchObject {
	final delayMs:Int64;
	final closeQueue:AsyncDeque<LuvTimerEvent>;
	final cont:IContinuation<Any>;
	var timer:Null<Timer>;
	var state:AtomicInt;

	public function new(closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, cont:IContinuation<Any>) {
		this.delayMs = ms;
		this.closeQueue = closeQueue;
		this.cont = cont;
		state = new AtomicInt(Created);
	}

	static function noOpCb() {}

	// only from loop thread

	public function start(loop:Loop) {
		if (state.compareExchange(Created, Started) != Created) {
			// Probably already cancelled
			return;
		}
		timer = Timer.init(loop).resolve();
		timer.start(run, Int64.toInt(delayMs));
	}

	public function stop() {
		if (state.compareExchange(Created, Stopped) == Created) {
			// Never started, nothing to do
			return false;
		}
		if (state.compareExchange(Started, Stopped) == Started) {
			// This is the expected state
			timer.stop();
			timer.close(noOpCb);
			timer = null;
			return true;
		}
		if (state.compareExchange(Cancelled, Stopped) == Cancelled) {
			// Cancelled
			timer.stop();
			timer.close(noOpCb);
			timer = null;
		}
		return false;
	}

	function run() {
		if (stop()) {
			cont.context.get(Dispatcher).dispatch(this);
		}
	}

	public function onDispatch() {
		cont.resume(null, null);
	}

	// maybe from other threads

	public function close() {
		if (state.compareExchange(Created, Stopped) == Created) {
			// Never started, nothing to do
			return;
		}
		if (state.compareExchange(Started, Cancelled) == Started) {
			// Add to queue so loop thread can close it
			closeQueue.add(this);
		}
		// Already cancelled or stopped, ignore
	}
}

/**
	A scheduler for a libuv loop.
**/
class LuvScheduler implements IScheduler {
	final loop:Loop;
	final eventQueue:AsyncDeque<LuvTimerEvent>;
	final closeQueue:AsyncDeque<LuvTimerEvent>;

	/**
		Creates a new `LuvScheduler` instance.
	**/
	public function new(loop:Loop) {
		this.loop = loop;
		eventQueue = new AsyncDeque(loop, loopEvents);
		closeQueue = new AsyncDeque(loop, loopCloses);
	}

	@:inheritDoc
	public function schedule(ms:Int64, cont:IContinuation<Any>) {
		final event = new LuvTimerEvent(closeQueue, ms, cont);
		eventQueue.add(event);
		return event;
	}

	@:inheritDoc
	public function now() {
		return loop.now().toInt64();
	}

	inline function consumeDeque<T>(deque:AsyncDeque<T>, f:T->Void) {
		do {
			final event = deque.pop(false);
			if (event == null) {
				break;
			}
			f(event);
		} while (true);
	}

	function loopEvents(_:Async) {
		consumeDeque(eventQueue, event -> event.start(loop));
	}

	function loopCloses(_:Async) {
		consumeDeque(closeQueue, event -> event.stop());
	}

	public function shutdown() {
		eventQueue.close();
		closeQueue.close();
		loopCloses(null);
	}
}