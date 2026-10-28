#if target.threaded
import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicObject;
import hxcoro.dispatchers.ThreadPoolDispatcher;
import hxcoro.run.Setup;
import hxcoro.schedulers.ThreadAwareScheduler;
import hxcoro.task.AbstractTask;
import hxcoro.thread.FixedThreadPool;
import sys.thread.Thread;

/**
	A `run` call observed by the `Watchdog`.
**/
class Watched {
	public final deadline:Float;

	final setup:LoopSetup;
	final rootTask:AtomicObject<Null<AbstractTask>>;

	public function new(setup:LoopSetup, deadline:Float) {
		this.setup = setup;
		this.deadline = deadline;
		rootTask = new AtomicObject(null);
	}

	/**
		Records the root task of the run, which `dump` then prints.
	**/
	public function setRootTask(task:Null<AbstractTask>) {
		rootTask.store(task);
	}

	/**
		Prints the task tree, scheduler and thread pool state of the run.
	**/
	public function dump() {
		// The task tree, scheduler and pool are read without synchronization while other threads might still be running.
		try {
			switch (rootTask.load()) {
				case null:
					Sys.println("Root task: not started");
				case task:
					Sys.println("Task tree:");
					dumpTask(task, "\t");
			}
			Std.downcast(setup.loop, ThreadAwareScheduler)?.dump();
			switch (Std.downcast(setup.dispatcher, ThreadPoolDispatcher)) {
				case null:
				case dispatcher:
					Std.downcast(@:privateAccess dispatcher.pool, FixedThreadPool)?.dump();
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

/**
	Terminates the test process if a single `run` call takes longer than `timeoutSeconds`, after
	printing the state of its task tree, thread pool and scheduler.

	The atest runner's own per-test timeout cannot fire while `run` blocks its thread, so without
	this a hang inside `run` blocks CI until the job times out.
**/
class Watchdog {
	static public var timeoutSeconds = 120.0;

	static final current = new AtomicObject<Null<Watched>>(null);
	static final started = new AtomicInt(0);

	static public function watch(setup:LoopSetup) {
		final watched = new Watched(setup, Sys.time() + timeoutSeconds);
		current.store(watched);
		if (started.exchange(1) == 0) {
			Thread.create(loop);
		}
		return watched;
	}

	static public function unwatch() {
		current.store(null);
	}

	static function loop() {
		while (true) {
			Sys.sleep(1);
			final watched = current.load();
			if (watched != null && Sys.time() > watched.deadline) {
				Sys.println("");
				Sys.println('WATCHDOG: run did not complete within ${timeoutSeconds}s');
				watched.dump();
				Sys.exit(2);
			}
		}
	}
}
#end
