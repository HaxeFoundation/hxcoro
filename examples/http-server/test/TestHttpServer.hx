import Http;
import HttpServer.Handler;
import RequestInfo.RequestLog;
import Tcp.TcpConnection;
import haxe.exceptions.CancellationException;
import hxcoro.concurrent.CoroLatch;
import hxcoro.task.ICoroNode;
import hxcoro.task.NodeLambda;

class TestHttpServer extends atest.Test {
	final logs:Array<String> = [];

	override function setup() {
		logs.resize(0);
		RequestLog.output = logs.push;
	}

	override function teardown() {
		RequestLog.output = Sys.println;
	}

	/**
		Runs `lambda` on a `LoopDispatcher`, failing if it takes longer than 5 seconds.
	**/
	static function runOnLoop<T>(lambda:NodeLambda<T>):T {
		final setup = LoopDispatcher.createSetup();
		final result = try {
			setup.createContext().runTask(node -> timeout(5000, lambda));
		} catch (e:haxe.Exception) {
			setup.close();
			throw e;
		}
		setup.close();
		return result;
	}

	/**
		Starts a server with `handler` as a child of `node`.
	**/
	@:coroutine static function startServer(node:ICoroNode, handler:Handler, requestTimeout = 1000) {
		final server = HttpServer.bind("127.0.0.1", 0, handler, requestTimeout);
		final task = node.async(_ -> server.serve());
		return {server: server, task: task};
	}

	static final hello:Handler = request -> Response.text(200, 'Hello ${request.path}');

	function testHello() {
		final response = runOnLoop(node -> {
			final s = startServer(node, hello);
			final response = HttpClient.get(s.server.port, "/world");
			s.server.stop();
			response;
		});
		Assert.equals(200, response.status);
		Assert.equals("Hello /world", response.body);
		Assert.equals("1", response.headers["x-request-id"]);
	}

	function testQueryAndBody() {
		final response = runOnLoop(node -> {
			final s = startServer(node, request -> Response.text(200, '${request.method} ${request.query["a"]} ${request.query["b"]} ${request.body}'));
			final response = HttpClient.send(s.server.port, "POST /?a=1&b=x%20y HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello");
			s.server.stop();
			response;
		});
		Assert.equals(200, response.status);
		Assert.equals("POST 1 x y hello", response.body);
	}

	function testRequestContextIsInherited() {
		final responses = runOnLoop(node -> {
			final s = startServer(node, request -> {
				// A grandchild task of the connection still sees the request's context.
				scope(node -> {
					node.async(_ -> {
						delay(1);
						RequestLog.log("from child task");
					});
				});
				Response.text(200, Std.string(RequestInfo.current().id));
			});
			final responses = [HttpClient.get(s.server.port, "/"), HttpClient.get(s.server.port, "/")];
			s.server.stop();
			responses;
		});
		Assert.same(["1", "2"], [for (response in responses) response.body]);
		Assert.same(["1", "2"], [for (response in responses) response.headers["x-request-id"]]);
		final childLogs = logs.filter(line -> StringTools.endsWith(line, "from child task"));
		Assert.equals(2, childLogs.length);
		Assert.isTrue(StringTools.startsWith(childLogs[0], "[#1 127.0.0.1:"));
		Assert.isTrue(StringTools.startsWith(childLogs[1], "[#2 127.0.0.1:"));
	}

	function testRequestsAreConcurrent() {
		final numRequests = 5;
		final responses = runOnLoop(node -> {
			// No request can complete before all of them have arrived.
			final latch = new CoroLatch(numRequests);
			final s = startServer(node, request -> {
				latch.arriveAndWait(1);
				Response.text(200, "ok");
			});
			final tasks = [for (_ in 0...numRequests) node.async(_ -> HttpClient.get(s.server.port, "/"))];
			final responses = [for (task in tasks) task.await()];
			s.server.stop();
			responses;
		});
		Assert.same([for (_ in 0...numRequests) 200], [for (response in responses) response.status]);
	}

	function testFailingHandlerDoesNotStopServer() {
		final responses = runOnLoop(node -> {
			final s = startServer(node, request -> {
				if (request.path == "/fail") {
					throw "oh no";
				}
				Response.text(200, "ok");
			});
			final responses = [HttpClient.get(s.server.port, "/fail"), HttpClient.get(s.server.port, "/")];
			s.server.stop();
			responses;
		});
		Assert.same([500, 200], [for (response in responses) response.status]);
	}

	function testHandlerTimeout() {
		var cancelled = false;
		final response = runOnLoop(node -> {
			final s = startServer(node, request -> {
				try {
					delay(10000);
				} catch (e:CancellationException) {
					cancelled = true;
					throw e;
				}
				Response.text(200, "ok");
			}, 100);
			final response = HttpClient.get(s.server.port, "/");
			s.server.stop();
			response;
		});
		Assert.equals(503, response.status);
		Assert.isTrue(cancelled);
	}

	function testSlowClientTimeout() {
		final response = runOnLoop(node -> {
			final s = startServer(node, hello, 100);
			// Connect, but never send a request.
			final response = HttpClient.send(s.server.port, "");
			s.server.stop();
			response;
		});
		Assert.equals(503, response.status);
	}

	function testBadRequest() {
		final response = runOnLoop(node -> {
			final s = startServer(node, hello);
			final response = HttpClient.send(s.server.port, "NONSENSE\r\n\r\n");
			s.server.stop();
			response;
		});
		Assert.equals(400, response.status);
	}

	function testGracefulShutdown() {
		var connectError:Null<haxe.Exception> = null;
		final response = runOnLoop(node -> {
			final s = startServer(node, request -> {
				delay(200);
				Response.text(200, "finished");
			});
			final request = node.async(_ -> HttpClient.get(s.server.port, "/"));
			delay(50);
			s.server.stop();
			// serve returns only after the request in flight has been handled.
			s.task.await();
			try {
				TcpConnection.connect("127.0.0.1", s.server.port);
			} catch (e:haxe.Exception) {
				connectError = e;
			}
			request.await();
		});
		Assert.equals(200, response.status);
		Assert.equals("finished", response.body);
		Assert.notNull(connectError);
	}

	function testCancellingServerCancelsRequests() {
		var cancelled = false;
		final response = runOnLoop(node -> {
			final s = startServer(node, request -> {
				try {
					delay(10000);
				} catch (e:CancellationException) {
					cancelled = true;
					throw e;
				}
				Response.text(200, "ok");
			});
			final request = node.async(_ -> HttpClient.get(s.server.port, "/"));
			delay(50);
			s.task.cancel();
			request.await();
		});
		Assert.isTrue(cancelled);
		// The connection was closed without a response.
		Assert.equals(0, response.status);
	}
}
