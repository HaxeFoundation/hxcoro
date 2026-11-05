package hxcoro.task;

#if hxcoro.trace_tasks
/**
	A lifecycle method call of a task.
**/
typedef TaskTraceEvent = {
	final task:AbstractTask;
	final method:String;
	/**
		The other task involved, e.g. the parent of a new task or the child that completed.
	**/
	final ?other:AbstractTask;
	final ?info:String;
	/**
		`true` when `method` is entered, `false` when it is left, `null` for an event without duration.
	**/
	final ?enter:Bool;
}

/**
	Records the lifecycle method calls of all tasks. Only available with `-D hxcoro.trace_tasks`;
	without it, the calls in the task classes compile to nothing.
**/
class TaskTrace {
	static var sink:Null<TaskTraceEvent->Void> = null;
	#if target.threaded
	static final mutex = new sys.thread.Mutex();
	#end

	/**
		Starts recording. Every event is passed to `sink`.
	**/
	public static function start(sink:TaskTraceEvent->Void) {
		TaskTrace.sink = sink;
	}

	/**
		Stops recording.
	**/
	public static function stop() {
		sink = null;
	}

	@:allow(hxcoro.task)
	static function log(task:AbstractTask, method:String, ?other:AbstractTask, ?info:String, ?enter:Bool) {
		final sink = sink;
		if (sink == null) {
			return;
		}
		#if target.threaded
		mutex.acquire();
		#end
		sink({task: task, method: method, other: other, info: info, enter: enter});
		#if target.threaded
		mutex.release();
		#end
	}
}
#else
class TaskTrace {
	public static inline function log(task:AbstractTask, method:String, ?other:AbstractTask, ?info:String, ?enter:Bool):Void {}
}
#end
