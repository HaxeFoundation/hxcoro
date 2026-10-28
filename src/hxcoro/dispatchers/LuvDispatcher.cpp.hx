package hxcoro.dispatchers;

import cpp.luv.Luv;
import cpp.luv.Work;
import haxe.Exception;
import haxe.atomic.AtomicBool;
import haxe.atomic.AtomicInt;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.ds.Option;
import hxcoro.schedulers.LuvScheduler;

/**
	A dispatcher that runs dispatched objects on the libuv thread pool of `loop`.

	If no `scheduler` is passed to the constructor, a `hxcoro.schedulers.LuvScheduler` for `loop`
	is created and owned by this dispatcher.
**/
class LuvDispatcher extends Dispatcher
{
	final loop:LuvLoop;
	final workQueue:AsyncDeque<IDispatchObject>;
	final s:IScheduler;
	// Only set if we create it
	final luvScheduler:Option<LuvScheduler>;
	// Objects that were dispatched but have not finished running yet
	final numPending:AtomicInt;
	final isShutDown:AtomicBool;

	function get_scheduler():IScheduler {
		return s;
	}

	public function new(loop:LuvLoop, ?scheduler:IScheduler) {
		this.loop = loop;
		numPending = new AtomicInt(0);
		isShutDown = new AtomicBool(false);

		workQueue  = new AsyncDeque(loop, @:nullSafety(Off) loopWork);
		if (scheduler == null) {
			final scheduler = new LuvScheduler(loop);
			s = scheduler;
			luvScheduler = Some(scheduler);
		} else {
			s = scheduler;
			luvScheduler = None;
		}
	}

	/**
		Runs `obj` on the libuv thread pool. Throws if this dispatcher has been shut down.
	**/
	public function dispatch(obj:IDispatchObject) {
		if (isShutDown.load()) {
			throw new Exception("LuvDispatcher has been shut down");
		}
		numPending.add(1);
		workQueue.add(obj);
	}

	function loopWork() {
		consumeDeque(workQueue, obj -> {
			Work.queue(loop, () -> {
				obj.onDispatch();
				numPending.sub(1);
			});
		});
	}

	/**
		Runs `loop` until all dispatched objects have finished, including objects that are
		dispatched while doing so. Then closes the internal libuv handle and shuts down the
		scheduler if it is owned by this dispatcher.

		Must be called from the thread that runs `loop`.
	**/
	public function shutDown() {
		while (numPending.load() > 0) {
			// Each finished work item wakes the loop up, so this does not miss the last one.
			Luv.runLoop(loop, Once);
		}
		isShutDown.store(true);
		workQueue.close();
		switch (luvScheduler) {
			case Some(s):
				s.shutDown();
			case None:
		}
	}
}
