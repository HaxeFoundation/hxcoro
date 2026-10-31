import eval.luv.Loop;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import hxcoro.run.Setup.LoopSetup;
import hxcoro.schedulers.LuvScheduler;

/**
	A dispatcher that runs all coroutines on the thread that runs the libuv `loop`.

	hxcoro's own `LuvDispatcher` runs coroutines on the libuv thread pool, but libuv handles such
	as sockets may only be used from the loop thread. With this dispatcher, coroutines can call
	libuv directly and everything runs on a single thread, like in Node.js.
**/
class LoopDispatcher extends Dispatcher {
	/**
		The libuv loop that runs the coroutines.
	**/
	public final loop:Loop;

	final luvScheduler:LuvScheduler;
	final queue:AsyncDeque<IDispatchObject>;

	public function new(loop:Loop) {
		this.loop = loop;
		luvScheduler = new LuvScheduler(loop);
		queue = new AsyncDeque(loop, _ -> LuvScheduler.consumeDeque(queue, obj -> obj.onDispatch()));
	}

	function get_scheduler():IScheduler {
		return luvScheduler;
	}

	public function dispatch(obj:IDispatchObject) {
		queue.add(obj);
	}

	/**
		Creates a setup that uses a `LoopDispatcher` on a new libuv loop.
	**/
	static public function createSetup() {
		final loop = Loop.init().resolve();
		final dispatcher = new LoopDispatcher(loop);
		function finalize() {
			dispatcher.luvScheduler.shutdown();
			dispatcher.queue.close();
			// Process the close callbacks of all handles before closing the loop.
			loop.run(NOWAIT);
			loop.close();
		}
		return new LoopSetup(dispatcher.luvScheduler, dispatcher, finalize);
	}

	/**
		Returns the libuv loop of the current coroutine's dispatcher, which has to be a
		`LoopDispatcher`.
	**/
	@:coroutine static public function currentLoop():Loop {
		final dispatcher = haxe.coro.CoroIntrinsics.getContext().getOrRaise(Dispatcher);
		if (dispatcher is LoopDispatcher) {
			return (cast dispatcher : LoopDispatcher).loop;
		}
		throw 'Expected a LoopDispatcher, got $dispatcher';
	}
}
