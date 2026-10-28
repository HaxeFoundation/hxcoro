#if target.threaded
import hxcoro.run.Setup;
import hxcoro.task.AbstractTask;
import sys.thread.Mutex;
import sys.thread.Thread;

private class Watched {
	public final setup:LoopSetup;
	public final deadline:Float;
	public var rootTask:Null<AbstractTask>;

	public function new(setup:LoopSetup, deadline:Float) {
		this.setup = setup;
		this.deadline = deadline;
	}
}

/**
	Terminates the test process if a single `run` call takes longer than `timeoutSeconds`, after
	printing the state of its task tree, thread pool and scheduler.

	The atest runner's own per-test timeout cannot fire while `run` blocks its thread, so without
	this a hang inside `run` blocks CI until the job times out.
**/
class Watchdog {
	static public var timeoutSeconds = 120.0;

	static final mutex = new Mutex();
	static var current:Null<Watched>;
	static var thread:Null<Thread>;

	static public function watch(setup:LoopSetup) {
		final watched = new Watched(setup, Sys.time() + timeoutSeconds);
		mutex.acquire();
		current = watched;
		thread ??= Thread.create(loop);
		mutex.release();
		return watched;
	}

	static public function unwatch() {
		mutex.acquire();
		current = null;
		mutex.release();
	}

	static function loop() {
		while (true) {
			Sys.sleep(1);
			mutex.acquire();
			final watched = current;
			mutex.release();
			if (watched != null && Sys.time() > watched.deadline) {
				Sys.println("");
				Sys.println('WATCHDOG: run did not complete within ${timeoutSeconds}s');
				dump(watched);
				Sys.exit(2);
			}
		}
	}

	static function dump(watched:Watched) {
		// Everything here is read without synchronization while other threads might still be running.
		try {
			switch (watched.rootTask) {
				case null:
					Sys.println("Root task: not started");
				case task:
					Sys.println("Task tree:");
					dumpTask(task, "\t");
			}
			if (watched.setup.loop is hxcoro.schedulers.ThreadAwareScheduler) {
				(cast watched.setup.loop : hxcoro.schedulers.ThreadAwareScheduler).dump();
			}
			final dispatcher = watched.setup.dispatcher;
			if (dispatcher is hxcoro.dispatchers.ThreadPoolDispatcher) {
				final pool = @:privateAccess (cast dispatcher : hxcoro.dispatchers.ThreadPoolDispatcher).pool;
				if (pool is hxcoro.thread.FixedThreadPool) {
					(cast pool : hxcoro.thread.FixedThreadPool).dump();
				}
			}
		} catch (e:Dynamic) {
			Sys.println('Dump failed: $e');
		}
	}

	@:access(hxcoro.task.AbstractTask)
	static function dumpTask(task:AbstractTask, indent:String) {
		final name = Type.getClassName(Type.getClass(task));
		Sys.println('$indent$name ${task.id}: state ${task.state.load().toString()}, active children ${task.numActiveChildren.load()}, error ${task.error.load()}');
		var child = task.firstChild;
		while (child != null) {
			dumpTask(child, indent + "\t");
			child = child.nextSibling;
		}
	}
}
#end
