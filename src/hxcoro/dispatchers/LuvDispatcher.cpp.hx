package hxcoro.dispatchers;

import cpp.luv.Luv;
import cpp.luv.Work;
import haxe.Exception;
import haxe.atomic.AtomicInt;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.ds.Option;
import hxcoro.concurrent.BackOff;
import hxcoro.schedulers.LuvScheduler;

/**
	A dispatcher that runs dispatched objects on the libuv thread pool of `loop`.

	If a dispatched object throws, the exception is printed, and the worker thread carries on.

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
	// Objects that were dispatched but have not finished running yet, or -1 once shut down
	final numPending:AtomicInt;

	function get_scheduler():IScheduler {
		return s;
	}

	public function new(loop:LuvLoop, ?scheduler:IScheduler) {
		this.loop = loop;
		numPending = new AtomicInt(0);

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
		// Increment and check in one step so that shutDown can't close the queue in between.
		while (true) {
			final old = numPending.load();
			if (old < 0) {
				throw new Exception("LuvDispatcher has been shut down");
			}
			if (numPending.compareExchange(old, old + 1) == old) {
				break;
			}
			BackOff.backOff();
		}
		workQueue.add(obj);
	}

	function loopWork() {
		consumeDeque(workQueue, obj -> {
			Work.queue(loop, () -> {
				try {
					obj.onDispatch();
				} catch (e:Exception) {
					// An exception escaping into libuv terminates the process, so report it the way
					// an uncaught exception on a Haxe thread is reported.
					Sys.println("THREAD ABORTED : " + e.message + haxe.CallStack.toString(e.stack));
				}
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
		// Switching from 0 to -1 atomically means that no dispatch can sneak in after the check.
		while (true) {
			switch (numPending.compareExchange(0, -1)) {
				case 0:
					break;
				case -1:
					// Already shut down
					return;
				case _:
					// Each finished work item wakes the loop up, so this does not miss the last one.
					Luv.runLoop(loop, Once);
			}
		}
		workQueue.close();
		switch (luvScheduler) {
			case Some(s):
				s.shutDown();
			case None:
		}
	}
}
