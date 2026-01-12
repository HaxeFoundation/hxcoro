package hxcoro.schedulers;

import sys.thread.Deque;
import sys.thread.Thread;
import hxcoro.dispatchers.SelfDispatcher;
import hxcoro.dispatchers.IDispatcher;
import haxe.Int64;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
import eval.luv.Timer;
import eval.luv.Loop;

private class LuvTimerEvent implements ISchedulerHandle {
	final dispatcher:IDispatcher;
	final delayMs:Int64;
	final closeQueue:Deque<LuvTimerEvent>;
	final obj:IScheduleObject;
	var closed:Bool;
	var timer:Null<Timer>;

	public function new(dispatcher:IDispatcher, closeQueue:Deque<LuvTimerEvent>, ms:Int64, obj:IScheduleObject) {
		this.dispatcher = dispatcher;
		this.delayMs = ms;
		this.closeQueue = closeQueue;
		this.obj = obj;
		closed = false;
	}

	// only from loop thread

	public function start(loop:Loop) {
		if (closed) {
			return;
		}
		timer = Timer.init(loop).resolve();
		timer.start(run, Int64.toInt(delayMs));
	}

	public function stop() {
		if (timer != null) {
			timer.stop();
			timer = null;
		}
	}

	function run() {
		if (closed) {
			stop();
			return;
		}
		dispatcher.dispatch(obj);
	}

	// maybe from other threads

	public function close() {
		if (closed) {
			return;
		}
		closed = true;
		if (timer != null) {
			// we need to do it like this because only the loop thread may close timers
			closeQueue.add(this);
		}
	}
}

private class LuvTimerEventFunction extends LuvTimerEvent implements IScheduleObject {
	final func:() -> Void;

	public function new(dispatcher:IDispatcher, closeQueue:Deque<LuvTimerEvent>, ms:Int64, func:() -> Void) {
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
	final loop:Loop;
	final dispatcher:IDispatcher;
	final loopThread:Thread;
	final eventQueue:Deque<LuvTimerEvent>;
	final closeQueue:Deque<LuvTimerEvent>;

	/**
		Creates a new `LuvScheduler` instance.
	**/
	public function new(loop:Loop, ?dispatcher:IDispatcher) {
		super();
		this.loop = loop;
		this.dispatcher = dispatcher ?? new SelfDispatcher();
		loopThread = Thread.current();
		eventQueue = new Deque();
		closeQueue = new Deque();
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

	public function run() {
		var event = eventQueue.pop(false);
		if (event != null) {
			event.start(loop);
		}

		// close all timers from the close-queue because we want to cancel promptly
		while ((event = closeQueue.pop(false)) != null) {
			event.stop();
		}
	}
}