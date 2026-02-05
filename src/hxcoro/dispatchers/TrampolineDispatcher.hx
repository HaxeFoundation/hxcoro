package hxcoro.dispatchers;

import haxe.coro.schedulers.IScheduler;
import haxe.exceptions.ArgumentException;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import hxcoro.schedulers.EventLoopScheduler;

private class Trampoline {
	public var running : Bool;
	public var queue : Null<Array<IDispatchObject>>;

	public function new() {
		running = false;
		queue   = null;
	}

	public static function get():Trampoline {
#if target.threaded
 		static final tls = {
			final l = new sys.thread.Tls<Null<Trampoline>>();
			l.value = null;
			l;
		}
		if (tls.value != null) {
			return tls.value;
		}
		final thread = sys.thread.Thread.current();
		thread.onExit(function() {
			tls.value = null;
		});
		final trampoline = new Trampoline();
		tls.value = trampoline;
		return trampoline;
#else
		static var trampoline : Null<Trampoline> = null;

		return trampoline ??= new Trampoline();
#end
	}
}

final class TrampolineDispatcher extends Dispatcher {
	final s : IScheduler;
	final trampoline : Trampoline;

	public function new(scheduler : IScheduler = null) {
		s          = scheduler ?? new EventLoopScheduler();
		trampoline = Trampoline.get();
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
