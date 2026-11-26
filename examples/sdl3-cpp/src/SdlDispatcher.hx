import SDL;
import cpp.marshal.RootHandle;
import haxe.Exception;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;

/**
	A dispatcher that runs dispatched objects on the thread that polls SDL's event queue.

	`dispatch` pushes an SDL user event that carries the object, which is thread-safe, so
	coroutines that use this dispatcher always resume on the main thread, no matter where
	they were resumed from. The main loop passes these events to `run`.
**/
class SdlDispatcher extends Dispatcher {
	/**
		The SDL event type of the events that carry dispatched objects.
	**/
	public final eventType:Int;

	final s:IScheduler;

	public function new(scheduler:IScheduler) {
		eventType = SDL.registerEvents(1);
		s = scheduler;
	}

	function get_scheduler() {
		return s;
	}

	public function dispatch(obj:IDispatchObject) {
		final event = new Event();
		event.type = eventType;
		// The object has to stay alive while only SDL's queue references it.
		event.user.data1 = RootHandle.create(obj).toVoidPointer();

		if (!SDL.pushEvent(event)) {
			throw new Exception("Failed to push dispatch event");
		}
	}

	/**
		Runs the object carried by `event`, which must be of type `eventType`.
	**/
	public function run(event:Event) {
		final root = RootHandle.fromVoidPointer(event.user.data1);
		final obj:IDispatchObject = root.getObject();
		root.close();

		obj.onDispatch();
	}
}
