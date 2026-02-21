package hxcoro.dispatchers;

import cpp.luv.Luv;
import cpp.luv.Work;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.ds.Option;
import hxcoro.schedulers.LuvScheduler;

class LuvDispatcher extends Dispatcher
{
	final loop:LuvLoop;
	final workQueue:AsyncDeque<()->Void>;
	final s:IScheduler;
	// Only set if we create it
	final luvScheduler:Option<LuvScheduler>;

	function get_scheduler():IScheduler {
		return s;
	}

	public function new(loop:LuvLoop, ?scheduler:IScheduler) {
		this.loop = loop;

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

	public function dispatch(obj:IDispatchObject) {
		workQueue.add(obj.onDispatch);
	}

	function loopWork() {
		consumeDeque(workQueue, event -> {
			Work.queue(loop, event);
		});
	}

	public function shutDown() {
		switch (luvScheduler) {
			case Some(s):
				s.shutDown();
			case None:
		}
		loopWork();
		workQueue.close();
	}
}