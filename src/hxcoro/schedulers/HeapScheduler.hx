package hxcoro.schedulers;

import haxe.coro.IContinuation;
import haxe.Timer;
import haxe.Int64;
import sys.thread.Mutex;
import haxe.exceptions.ArgumentException;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;

/**
	Base class for schedulers that keep scheduled events in a `MinimumHeap` ordered by due time.
**/
class HeapScheduler implements IScheduler {
	final futureMutex : Mutex;
	final heap : MinimumHeap;

	public function new() {
		futureMutex  = new Mutex();
		heap         = new MinimumHeap();
	}

    public function schedule(ms:Int64, cont:IContinuation<Any>):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		final event = new ScheduledEvent(cont, now() + ms);

		futureMutex.acquire();

		heap.insert(event);

		futureMutex.release();

		return event;
    }

	public function now():Int64 {
		#if lua_vanilla
		// Timer.stamp() calls Sys.time() which is not available in -D lua-vanilla.
		// Use lua.Os.clock() (CPU time, seconds) as a substitute.
		return haxe.Int64.ofInt(Std.int(lua.Os.clock() * 1000));
		#else
		return Timer.milliseconds();
		#end
	}

}
