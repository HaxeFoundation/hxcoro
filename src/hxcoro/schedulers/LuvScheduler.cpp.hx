package hxcoro.schedulers;

import cpp.luv.Luv;
import haxe.Int64;
import haxe.atomic.AtomicInt;
import haxe.coro.IContinuation;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;

import hxcoro.schedulers.ILoop;
import sys.thread.Deque;

using cpp.luv.Async;
using cpp.luv.Timer;

class AsyncDeque<T> {
	final deque:Deque<T>;
	var async:LuvAsync;

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

private class LuvTimerEvent implements ISchedulerHandle implements IDispatchObject {
	final delayMs:Int64;
	final closeQueue:AsyncDeque<LuvTimerEvent>;
	final cont:IContinuation<Any>;
	var timer:Null<LuvTimer>;
	var state:AtomicInt;

	public function new(closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, cont:IContinuation<Any>) {
		this.delayMs = ms;
		this.closeQueue = closeQueue;
		this.cont = cont;
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

	@:nullSafety(Off)
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

inline function consumeDeque<T>(deque:AsyncDeque<T>, f:T->Void) {
	do {
		final event = deque.pop(false);
		if (event == null) {
			break;
		}
		f(event);
	} while (true);
}

/**
	A scheduler for a libuv loop.
**/
class LuvScheduler implements IScheduler implements ILoop {
	final uvLoop:LuvLoop;
	final eventQueue:AsyncDeque<LuvTimerEvent>;
	final closeQueue:AsyncDeque<LuvTimerEvent>;

	/**
		Creates a new `LuvScheduler` instance.
	**/
	public function new(uvLoop:LuvLoop) {
		this.uvLoop = uvLoop;
		eventQueue = new AsyncDeque(uvLoop, @:nullSafety(Off) loopEvents);
		closeQueue = new AsyncDeque(uvLoop, @:nullSafety(Off) loopCloses);
	}

	@:inheritDoc
	public function schedule(ms:Int64, cont:IContinuation<Any>) {
		final event = new LuvTimerEvent(closeQueue, ms, cont);
		eventQueue.add(event);
		return event;
	}

	@:inheritDoc
	public function now() {
		return haxe.Timer.milliseconds(); // TODO: where?
	}

	function loopEvents() {
		consumeDeque(eventQueue, event -> event.start(uvLoop));
	}

	function loopCloses() {
		consumeDeque(closeQueue, event -> event.stop());
	}

	public function loop(runMode:RunMode) {
		cpp.luv.Luv.runLoop(uvLoop, cast runMode);
	}

	public function wakeUp() {
		@:privateAccess eventQueue.async.send();
	}

	public function shutDown() {
		eventQueue.close();
		closeQueue.close();
		loopCloses();
	}
}