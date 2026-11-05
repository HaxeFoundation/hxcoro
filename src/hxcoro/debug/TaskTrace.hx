package hxcoro.debug;

#if hxcoro.trace_tasks
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import hxcoro.task.AbstractTask;
import sys.thread.Tls;

/**
	A lifecycle method call of a task. The `run` method is not a method of the task but the time its
	coroutine body runs after a suspension.
**/
typedef TaskTraceEvent = {
	final task:AbstractTask;
	final method:String;
	/**
		Identifies the thread the call happened on: 1 for the first thread the element saw, and so on.
	**/
	final threadId:Int;
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
	final threadIds = new Tls<Int>();
	var nextThreadId = 0;
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

	@:allow(hxcoro)
	function log(task:AbstractTask, method:String, ?other:AbstractTask, ?info:String, ?enter:Bool) {
		#if target.threaded
		mutex.acquire();
		#end
		var threadId:Null<Int> = threadIds.value;
		if (threadId == null || threadId == 0) {
			threadId = ++nextThreadId;
			threadIds.value = threadId;
		}
		sink({task: task, method: method, threadId: threadId, other: other, info: info, enter: enter});
		#if target.threaded
		mutex.release();
		#end
	}
}
#end
