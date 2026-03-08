package hxcoro.dispatchers;

import eval.luv.Result;
import eval.luv.ThreadPool;
import eval.luv.Loop;
import eval.luv.Async;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.ds.Option;
import hxcoro.schedulers.LuvScheduler;

class LuvDispatcher extends Dispatcher
{
	final loop:Loop;
	final workQueue:AsyncDeque<()->Void>;
	final s:IScheduler;
	// Only set if we create it
	final luvScheduler:Option<LuvScheduler>;

	function get_scheduler():IScheduler {
		return s;
	}

	public function new(loop:Loop, ?scheduler:IScheduler) {
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

	function loopWork(_:Null<Async>) {
		LuvScheduler.consumeDeque(workQueue, event -> {
			ThreadPool.queueWork(loop, null, event, noOpCb);
		});
	}

	public function shutDown() {
		switch (luvScheduler) {
			case Some(s):
				s.shutdown();
			case None:
		}
		loopWork(null);
		workQueue.close();
	}

	function noOpCb(_:Result<Any>) {}
}