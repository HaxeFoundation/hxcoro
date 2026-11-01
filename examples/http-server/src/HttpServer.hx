import Http;
import RequestInfo.RequestLog;
import Tcp;
import haxe.coro.Coroutine;
import haxe.exceptions.CancellationException;
import hxcoro.Coro.*;
import hxcoro.exceptions.TimeoutException;

using hxcoro.util.Convenience;

typedef Handler = Coroutine<(request:Request) -> Response>;

/**
	An HTTP server that handles each connection in its own task.

	The task tree looks like this:

	```
	serve()
	└── supervisor
	    ├── connection #1
	    │   └── timeout
	    │       └── handler, and any tasks it starts
	    ├── connection #2
	    ...
	```

	The supervisor keeps the server running if a connection's task fails, while still making sure
	that `serve` doesn't return before every connection has been handled. Cancelling `serve`
	cancels every connection.
**/
class HttpServer {
	/**
		The port the server listens on.
	**/
	public final port:Int;

	final listener:TcpListener;
	final handler:Handler;
	final requestTimeout:Int;

	function new(listener:TcpListener, handler:Handler, requestTimeout:Int) {
		this.listener = listener;
		this.handler = handler;
		this.requestTimeout = requestTimeout;
		port = listener.port;
	}

	/**
		Creates a server listening on `host` and `port` that responds to requests with `handler`.
		If reading a request and handling it takes longer than `requestTimeout` milliseconds, the
		handler is cancelled and the client receives a 503 response.

		Requests are only accepted once `serve` is called.
	**/
	@:coroutine static public function bind(host:String, port:Int, handler:Handler, requestTimeout:Int) {
		return new HttpServer(TcpListener.bind(host, port), handler, requestTimeout);
	}

	/**
		Accepts and handles connections until `stop` is called, then returns once all requests
		have been handled.
	**/
	@:coroutine public function serve() {
		try {
			supervisor(node -> {
				var nextId = 1;
				while (true) {
					final connection = listener.accept();
					if (connection == null) {
						break;
					}
					final info = new RequestInfo(nextId++, connection.peerName());
					node.with(info).async(_ -> handleConnection(connection));
				}
				// The supervisor now waits for the connections that are still being handled.
			});
		} catch (e:haxe.Exception) {
			listener.close();
			throw e;
		}
	}

	/**
		Stops accepting connections. Requests that are already being handled are not affected.
	**/
	public function stop() {
		listener.close();
	}

	@:coroutine function handleConnection(connection:TcpConnection) {
		try {
			final response = respond(connection);
			if (response != null) {
				send(connection, response);
			}
		} catch (e:haxe.Exception) {
			connection.close();
			throw e;
		}
		connection.close();
	}

	@:coroutine function respond(connection:TcpConnection):Null<Response> {
		try {
			// The timeout also covers reading the request, so slow clients can't hold on to a
			// connection.
			return timeout(requestTimeout, _ -> {
				final request = HttpParser.readRequest(connection);
				if (request == null) {
					return null;
				}
				RequestLog.log('${request.method} ${request.path}');
				return handler(request);
			});
		} catch (e:TimeoutException) {
			RequestLog.log("Timed out");
			return Response.text(503, "Request timed out\n");
		} catch (e:BadRequestException) {
			RequestLog.log('Bad request: ${e.message}');
			return Response.text(400, e.message + "\n");
		} catch (e:CancellationException) {
			throw e;
		} catch (e:haxe.Exception) {
			// Tell the client, then let the task fail. Thanks to the supervisor, this doesn't affect
			// the server or other requests.
			RequestLog.log('Handler failed: ${e.message}');
			send(connection, Response.text(500, "Internal Server Error\n"));
			throw e;
		}
	}

	@:coroutine function send(connection:TcpConnection, response:Response) {
		final info = RequestInfo.current();
		if (info != null) {
			response.headers["X-Request-Id"] = Std.string(info.id);
		}
		connection.write(response.toBytes());
		RequestLog.log('${response.status}');
	}
}
