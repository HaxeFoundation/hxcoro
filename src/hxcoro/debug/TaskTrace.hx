package hxcoro.debug;

#if hxcoro.trace_tasks
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import hxcoro.task.AbstractTask;

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
	A context element that records the lifecycle method calls of every task created in its context.
	Only available with `-D hxcoro.trace_tasks`.
**/
class TaskTrace implements IElement<TaskTrace> {
	/**
		The key under which this element is stored in a `Context`.
	**/
	static public final key = new Key<TaskTrace>("TaskTrace");

	final sink:TaskTraceEvent->Void;
	#if target.threaded
	final mutex = new sys.thread.Mutex();
	#end

	/**
		Creates an element that passes every event to `sink`, one at a time.
	**/
	public function new(sink:TaskTraceEvent->Void) {
		this.sink = sink;
	}

	public function getKey() {
		return key;
	}

	@:allow(hxcoro.task)
	function log(task:AbstractTask, method:String, ?other:AbstractTask, ?info:String, ?enter:Bool) {
		#if target.threaded
		mutex.acquire();
		#end
		sink({task: task, method: method, other: other, info: info, enter: enter});
		#if target.threaded
		mutex.release();
		#end
	}
}
#end
