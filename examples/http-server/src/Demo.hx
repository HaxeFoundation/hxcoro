import Http;
import RequestInfo.RequestLog;
import eval.luv.Signal.SigNum;
import haxe.exceptions.CancellationException;
import hxcoro.Coro.*;
import hxcoro.task.ICoroTask;

using hxcoro.run.ContextRun;

/**
	Runs a server on port 8080 with a few routes that show what happens in different situations.
**/
function main() {
	final setup = LoopDispatcher.createSetup();
	setup.createContext().runTask(node -> {
		var server:Null<HttpServer> = null;
		server = HttpServer.bind("127.0.0.1", 8080, request -> {
			switch (request.path) {
				case "/":
					final info = RequestInfo.current();
					Response.text(200, 'Hello, you are request #${info.id}\n');
				case "/slow":
					// Longer than the request timeout for ms > 5000.
					delay(Std.parseInt(request.query["ms"] ?? "1000") ?? 1000);
					Response.text(200, "Done\n");
				case "/fail":
					throw "Something went wrong";
				case "/lookup":
					// Child tasks inherit the request's context, so their log messages carry its id.
					final results = scope(node -> {
						final tasks = [for (name in ["users", "orders", "prices"]) node.async(_ -> {
							RequestLog.log('Looking up $name');
							delay(100);
							'$name: ok';
						})];
						[for (task in tasks) task.await()];
					});
					Response.text(200, results.join("\n") + "\n");
				case "/shutdown":
					server.stop();
					Response.text(200, "Shutting down after the remaining requests\n");
				case _:
					Response.text(404, "Not found\n");
			}
		}, 5000);
		RequestLog.log('Listening on http://127.0.0.1:${server.port}/, press Ctrl+C to stop');
		final serving = node.async(_ -> server.serve());
		node.async(_ -> handleInterrupts(server, serving));
		try {
			serving.await();
			RequestLog.log("Server stopped");
		} catch (e:CancellationException) {
			RequestLog.log("Server cancelled");
		}
		// The server can also stop because of /shutdown. Stop waiting for Ctrl+C then, or the
		// program would never end.
		node.cancelChildren();
	});
	setup.close();
}

/**
	Stops `server` gracefully on the first Ctrl+C, and cancels the requests it is still handling on
	the second one.
**/
@:coroutine function handleInterrupts(server:HttpServer, serving:ICoroTask<Void>) {
	final interrupts = SignalListener.listen(SIGINT);
	try {
		interrupts.next();
		RequestLog.log("Stopping after the remaining requests, press Ctrl+C again to cancel them");
		server.stop();
		interrupts.next();
		serving.cancel();
	} catch (e:haxe.Exception) {
		interrupts.close();
		throw e;
	}
	interrupts.close();
}
