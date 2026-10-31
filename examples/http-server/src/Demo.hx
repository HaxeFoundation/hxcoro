import Http;
import RequestInfo.RequestLog;
import hxcoro.Coro.*;

using hxcoro.run.ContextRun;

/**
	Runs a server on port 8080 with a few routes that show what happens in different situations.
**/
function main() {
	final setup = SelectScheduler.createSetup();
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
		RequestLog.log('Listening on http://127.0.0.1:${server.port}/');
		server.serve();
		RequestLog.log("Server stopped");
	});
	setup.close();
}
