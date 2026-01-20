package hxcoro.schedulers;

import eval.luv.Async;
import haxe.atomic.AtomicInt;
import sys.thread.Deque;
import haxe.Int64;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.coro.dispatchers.IDispatchObject;
import eval.luv.Timer;
import eval.luv.Loop;

class AsyncDeque<T> {
	final deque:Deque<T>;
	var async:Null<Async>;

	public function new(loop:Loop, f:Async -> Void) {
		this.deque = new Deque<T>();
		this.async = Async.init(loop, f).resolve();
	}

	public function add(x:T) {
		deque.add(x);
		async.send();
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

private class LuvTimerEvent implements ISchedulerHandle {
	final delayMs:Int64;
	final closeQueue:AsyncDeque<LuvTimerEvent>;
	final obj:IDispatchObject;
	var timer:Null<Timer>;
	var state:AtomicInt;

	public function new(closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, obj:IDispatchObject) {
		this.delayMs = ms;
		this.closeQueue = closeQueue;
		this.obj = obj;
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
			obj.onDispatch();
		}
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

private class LuvTimerEventFunction extends LuvTimerEvent implements IDispatchObject {
	final func:() -> Void;

	public function new(closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, func:() -> Void) {
		super(closeQueue, ms, this);
		this.func = func;
	}

	public function onDispatch() {
		func();
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
	public function schedule(ms:Int64, func:() -> Void) {
		final event = new LuvTimerEventFunction(closeQueue, ms, func);
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
	}
}