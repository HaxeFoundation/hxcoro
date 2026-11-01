import haxe.coro.CoroIntrinsics;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;

/**
	A context element that identifies the request a coroutine works on.

	`HttpServer` adds it to the context of each connection's task. Every coroutine and child task
	started while handling the request inherits it, so code anywhere in the handler can find out
	which request it belongs to without passing it around.
**/
class RequestInfo implements IElement<RequestInfo> {
	static public final key = new Key<RequestInfo>("RequestInfo");

	/**
		A number that identifies the request, counting from 1 for each server.
	**/
	public final id:Int;

	/**
		The address of the client.
	**/
	public final peer:String;

	public function new(id:Int, peer:String) {
		this.id = id;
		this.peer = peer;
	}

	public function getKey() {
		return key;
	}

	/**
		Returns the `RequestInfo` of the current coroutine, or `null` if it doesn't handle a request.
	**/
	@:coroutine static public function current():Null<RequestInfo> {
		return CoroIntrinsics.getContext().get(key);
	}
}

/**
	Logging that prefixes each message with the current request, if there is one.
**/
class RequestLog {
	/**
		Where messages go.
	**/
	static public var output:String -> Void = Sys.println;

	@:coroutine static public function log(message:String) {
		final info = RequestInfo.current();
		output(info == null ? message : '[#${info.id} ${info.peer}] $message');
	}
}
