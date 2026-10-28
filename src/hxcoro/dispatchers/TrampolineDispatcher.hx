package hxcoro.dispatchers;

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

		if (false == trampoline.running) {
			trampoline.running = true;

			obj.onDispatch();

			if (null == trampoline.queue) {
				trampoline.running = false;

				return;
			}

			var next = null;
			while (null != (next = trampoline.queue.shift())) {
				next.onDispatch();
			}

			trampoline.running = false;
			trampoline.queue   = null;

		} else {
			trampoline.queue ??= [];
			trampoline.queue.push(obj);
		}
	}
}
