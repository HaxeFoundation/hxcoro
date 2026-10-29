package hxcoro.dispatchers;

import haxe.Exception;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.exceptions.ArgumentException;
import sys.thread.Tls;
import hxcoro.schedulers.RealTimeScheduler;

private class Trampoline {
	public var running : Bool;
	public var queue : Null<Array<IDispatchObject>>;

	public function new() {
		running = false;
		queue   = null;
	}

	public static function get(tls:Tls<Trampoline>):Trampoline {
		final value = tls.value;
		if (value != null) {
			return value;
		}
		#if target.threaded
		sys.thread.Thread.addCurrentCallbacks({onExit: () -> {
			tls.value = null;
		}});
		#end
		final trampoline = new Trampoline();
		tls.value = trampoline;
		return trampoline;
	}
}

/**
	A dispatcher that runs dispatched objects immediately on the calling thread. Objects that are
	dispatched while another one is running on the same thread are queued and run after it returns,
	which avoids deep recursion.

	If a dispatched object throws, the exception propagates to the caller of `dispatch` right away.
	Objects that are still queued at that point stay queued and run first on the next `dispatch` on
	the same thread.

	If no `scheduler` is passed to the constructor, a `hxcoro.schedulers.RealTimeScheduler` is used.
**/
final class TrampolineDispatcher extends Dispatcher {
	final s : IScheduler;
	final trampolineTls : Tls<Trampoline>;

	public function new(scheduler : IScheduler = null) {
		s             = scheduler ?? new RealTimeScheduler();
		trampolineTls = new Tls();
	}

	public function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IDispatchObject) {
		if (null == obj) {
			throw new ArgumentException("obj");
		}

		final trampoline = Trampoline.get(trampolineTls);

		if (trampoline.running) {
			trampoline.queue ??= [];
			trampoline.queue.push(obj);
			return;
		}

		trampoline.running = true;
		try {
			final leftovers = trampoline.queue;
			if (leftovers != null && leftovers.length > 0) {
				// A previous dispatch threw and left these behind, they go first.
				leftovers.push(obj);
			} else {
				obj.onDispatch();
			}
			final queue = trampoline.queue;
			if (queue != null) {
				var next = null;
				while (null != (next = queue.shift())) {
					next.onDispatch();
				}
			}
		} catch (e:Exception) {
			// Leave the trampoline usable. Whatever is still queued runs on the next dispatch.
			trampoline.running = false;
			throw e;
		}

		trampoline.running = false;
		trampoline.queue   = null;
	}
}
