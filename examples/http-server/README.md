# HTTP server

A small HTTP server that shows structured concurrency with a real-world shape:

- `HttpServer.serve` runs a `supervisor` with one child task per connection. If a handler fails, the client receives a 500 response and the connection's task fails, but the supervisor keeps the server running.
- Each connection reads and handles its request inside a `timeout`. If that takes too long, the handler and every task it started are cancelled, and the client receives a 503 response.
- `stop` closes the listener. `serve` then returns once the requests that are still being handled have finished. Cancelling `serve` instead cancels them.
- Each connection's task has a `RequestInfo` element in its context. The handler and all tasks it starts inherit it, so `RequestLog.log` can prefix messages with the request's id without anything being passed around.

```haxe
final server = HttpServer.bind("127.0.0.1", 8080, request -> {
	final results = scope(node -> {
		final tasks = [for (name in ["users", "orders"]) node.async(_ -> {
			RequestLog.log('Looking up $name'); // [#2 127.0.0.1:54168] Looking up users
			lookUp(name);
		})];
		[for (task in tasks) task.await()];
	});
	Response.text(200, results.join("\n"));
}, 5000);
server.serve();
```

The server only works on eval, because it uses libuv through `eval.luv` for sockets:

- [LoopDispatcher.hx](src/LoopDispatcher.hx) is a dispatcher that runs all coroutines on the libuv loop thread, like Node.js. hxcoro's `LuvDispatcher` runs coroutines on the libuv thread pool instead, but libuv handles may only be used from the loop thread.
- [Tcp.hx](src/Tcp.hx) turns libuv's callback-based TCP API into coroutines using `suspendCancellable`. Cancelling an `accept` or `read` call stops waiting for it.
- [Http.hx](src/Http.hx) is a minimal HTTP/1.1 parser. Every response closes the connection, so there is no keep-alive or chunked encoding.

## Running

Run the tests from the repository root with:

```bash
haxe --cwd examples/http-server build-eval.hxml
```

[demo.hxml](demo.hxml) runs [Demo.hx](src/Demo.hx), a server on port 8080 with these routes:

| Route | Response |
| --- | --- |
| `/` | Says hello |
| `/slow?ms=1000` | Responds after `ms` milliseconds, or with a 503 after 5 seconds |
| `/fail` | Throws, so the client receives a 500 |
| `/lookup` | Runs three lookups in parallel child tasks that log with the request's id |
| `/shutdown` | Stops the server once the remaining requests have been handled |

```bash
haxe --cwd examples/http-server demo.hxml
curl http://127.0.0.1:8080/lookup
```

Press Ctrl+C once to stop the server after the remaining requests, and a second time to cancel them. The demo waits for Ctrl+C in a task next to the server, using [SignalListener.hx](src/SignalListener.hx). Once the server has stopped, for any reason, the demo cancels that task, because otherwise the program would wait for it forever.
