package hxcoro.schedulers;

import eval.luv.Async;
import haxe.atomic.AtomicInt;
import sys.thread.Deque;
import hxcoro.dispatchers.SelfDispatcher;
import hxcoro.dispatchers.IDispatcher;
import haxe.Int64;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
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
		async.send();
		async.close(() -> {});
	}
}

private enum abstract LuvTimerEventState(Int) to Int {
	final Created;
	final Started;
	final Cancelled;
	final Stopped;
}

private class LuvTimerEvent implements ISchedulerHandle {
	final dispatcher:IDispatcher;
	final delayMs:Int64;
	final closeQueue:AsyncDeque<LuvTimerEvent>;
	final obj:IScheduleObject;
	var timer:Null<Timer>;
	var state:AtomicInt;

	public function new(dispatcher:IDispatcher, closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, obj:IScheduleObject) {
		this.dispatcher = dispatcher;
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
			dispatcher.dispatch(obj);
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

private class LuvTimerEventFunction extends LuvTimerEvent implements IScheduleObject {
	final func:() -> Void;

	public function new(dispatcher:IDispatcher, closeQueue:AsyncDeque<LuvTimerEvent>, ms:Int64, func:() -> Void) {
		super(dispatcher, closeQueue, ms, this);
		this.func = func;
	}

	public function onSchedule() {
		func();
	}
}

/**
	A scheduler for a libuv loop.
**/
class LuvScheduler extends Scheduler {
	public var isShutdown(default, null):Bool;

	final loop:Loop;
	final dispatcher:IDispatcher;
	final eventQueue:AsyncDeque<LuvTimerEvent>;
	final closeQueue:AsyncDeque<LuvTimerEvent>;

	/**
		Creates a new `LuvScheduler` instance.
	**/
	public function new(loop:Loop, ?dispatcher:IDispatcher) {
		super();
		isShutdown = false;
		this.loop = loop;
		this.dispatcher = dispatcher ?? new SelfDispatcher();
		eventQueue = new AsyncDeque(loop, loopEvents);
		closeQueue = new AsyncDeque(loop, loopCloses);
	}

	@:inheritDoc
	function schedule(ms:Int64, func:() -> Void) {
		final event = new LuvTimerEventFunction(dispatcher, closeQueue, ms, func);
		eventQueue.add(event);
		return event;
	}

	@:inheritDoc
	function scheduleObject(obj:IScheduleObject) {
		final event = new LuvTimerEvent(dispatcher, closeQueue, 0, obj);
		eventQueue.add(event);
	}

	@:inheritDoc
	function now() {
		return loop.now().toInt64();
	}

	function loopEvents(_:Async) {
		do {
			final event = eventQueue.pop(false);
			if (event == null) {
				break;
			}
			event.start(loop);
		} while(true);
	}

	function loopCloses(_:Async) {
		do {
			final event = closeQueue.pop(false);
			if (event == null) {
				break;
			}
			event.stop();
		} while (true);
	}

	public function shutdown() {
		if (isShutdown) {
			return;
		}
		isShutdown = true;
		eventQueue.close();
		closeQueue.close();
	}
}