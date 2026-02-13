package hxcoro.dispatchers;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.exceptions.ArgumentException;
import hxcoro.concurrent.Tls;
import hxcoro.schedulers.EventLoopScheduler;

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
		final thread = sys.thread.Thread.current();
		thread.onExit(function() {
			tls.value = null;
		});
		#end
		final trampoline = new Trampoline();
		tls.value = trampoline;
		return trampoline;
	}
}

final class TrampolineDispatcher extends Dispatcher {
	final s : IScheduler;
	final trampoline : Trampoline;
	final trampolineTls : Tls<Trampoline>;

	public function new(scheduler : IScheduler = null) {
		s             = scheduler ?? new EventLoopScheduler();
		trampolineTls = new Tls();
		trampoline    = Trampoline.get(trampolineTls);
	}

	public function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IDispatchObject) {
		if (null == obj) {
			throw new ArgumentException("obj");
		}

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
