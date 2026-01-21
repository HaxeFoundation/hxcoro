package hxcoro.schedulers;

import haxe.atomic.AtomicInt;
import sys.thread.Deque;
import haxe.Int64;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.ISchedulerHandle;

import cpp.luv.Luv;
using cpp.luv.Async;
using cpp.luv.Timer;

class AsyncDeque<T> {
	final deque:Deque<T>;
	var async:Null<LuvAsync>;

	public function new(loop:LuvLoop, f:() -> Void) {
		this.deque = new Deque<T>();
		this.async = Async.init(loop, f);
	}

	public function add(x:T) {
		deque.add(x);
		async.send();
	}

	public function pop(block:Bool) {
		return deque.pop(block);
	}

	public function close() {
		async.close();
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
	var timer:Null<LuvTimer>;
	var state:AtomicInt;

	public function new(closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, obj:IDispatchObject) {
		this.delayMs = ms;
		this.closeQueue = closeQueue;
		this.obj = obj;
		state = new AtomicInt(Created);
	}

	// only from loop thread

	public function start(loop:LuvLoop) {
		if (state.compareExchange(Created, Started) != Created) {
			// Probably already cancelled
			return;
		}
		timer = Timer.repeat(loop, Int64.toInt(delayMs), run);
	}

	public function stop() {
		if (state.compareExchange(Created, Stopped) == Created) {
			// Never started, nothing to do
			return false;
		}
		if (state.compareExchange(Started, Stopped) == Started) {
			// This is the expected state
			timer.stop();
			timer.close();
			timer = null;
			return true;
		}
		if (state.compareExchange(Cancelled, Stopped) == Cancelled) {
			// Cancelled
			timer.stop();
			timer.close();
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
	final loop:LuvLoop;
	final eventQueue:AsyncDeque<LuvTimerEvent>;
	final closeQueue:AsyncDeque<LuvTimerEvent>;

	/**
		Creates a new `LuvScheduler` instance.
	**/
	public function new(loop:LuvLoop) {
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
		return haxe.Timer.milliseconds(); // TODO: where?
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

	function loopEvents() {
		consumeDeque(eventQueue, event -> event.start(loop));
	}

	function loopCloses() {
		consumeDeque(closeQueue, event -> event.stop());
	}

	public function shutdown() {
		eventQueue.close();
		closeQueue.close();
		loopCloses();
	}
}