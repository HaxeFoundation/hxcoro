import eval.luv.Buffer;
import eval.luv.Loop;
import eval.luv.LuvException;
import eval.luv.SockAddr;
import eval.luv.Tcp as UvTcp;
import haxe.coro.IContinuation;
import haxe.io.Bytes;
import hxcoro.Coro.*;

/**
	A TCP socket that listens for incoming connections.

	Like everything that uses libuv handles, this may only be used from coroutines running on a
	`LoopDispatcher`.
**/
class TcpListener {
	/**
		The port the listener is bound to, which is useful when binding to port 0.
	**/
	public final port:Int;

	final loop:Loop;
	final tcp:UvTcp;
	final pending = new List<TcpConnection>();
	var waiter:Null<IContinuation<Null<TcpConnection>>>;
	var closed = false;

	function new(loop:Loop, tcp:UvTcp) {
		this.loop = loop;
		this.tcp = tcp;
		port = tcp.getSockName().resolve().port;
		tcp.listen(onConnection);
	}

	/**
		Creates a listener bound to `host` and `port`.
	**/
	@:coroutine static public function bind(host:String, port:Int) {
		final loop = LoopDispatcher.currentLoop();
		final tcp = UvTcp.init(loop).resolve();
		switch (tcp.bind(SockAddr.ipv4(host, port).resolve())) {
			case Ok(_):
				return new TcpListener(loop, tcp);
			case Error(e):
				tcp.close(() -> {});
				throw new LuvException(e);
		}
	}

	function onConnection(result:eval.luv.Result<eval.luv.Result.NoData>) {
		if (closed || !result.isOk()) {
			return;
		}
		final client = UvTcp.init(loop).resolve();
		tcp.accept(client).resolve();
		final connection = new TcpConnection(client);
		final waiter = waiter;
		if (waiter != null) {
			this.waiter = null;
			waiter.resume(connection, null);
		} else {
			pending.add(connection);
		}
	}

	/**
		Suspends until a client connects and returns the connection, or returns `null` once the
		listener has been closed.
	**/
	@:coroutine public function accept():Null<TcpConnection> {
		if (!pending.isEmpty()) {
			return pending.pop();
		}
		if (closed) {
			return null;
		}
		return suspendCancellable(cont -> {
			waiter = cont;
			_ -> {
				waiter = null;
			}
		});
	}

	/**
		Stops listening. A pending `accept` call returns `null`.
	**/
	public function close() {
		if (closed) {
			return;
		}
		closed = true;
		tcp.close(() -> {});
		for (connection in pending) {
			connection.close();
		}
		pending.clear();
		final waiter = waiter;
		if (waiter != null) {
			this.waiter = null;
			waiter.resume(null, null);
		}
	}
}

/**
	A connected TCP socket.
**/
class TcpConnection {
	final tcp:UvTcp;
	var eof = false;
	var closed = false;

	public function new(tcp:UvTcp) {
		this.tcp = tcp;
	}

	/**
		Connects to `host` and `port`.
	**/
	@:coroutine static public function connect(host:String, port:Int) {
		final tcp = UvTcp.init(LoopDispatcher.currentLoop()).resolve();
		final address = SockAddr.ipv4(host, port).resolve();
		try {
			suspendCancellable(cont -> {
				tcp.connect(address, result -> switch (result) {
					case Ok(_):
						cont.resume(true, null);
					case Error(e):
						cont.resume(false, new LuvException(e));
				});
				// Closing the handle aborts the connection attempt.
				_ -> tcp.close(() -> {});
			});
		} catch (e:haxe.Exception) {
			if (!tcp.isClosing()) {
				tcp.close(() -> {});
			}
			throw e;
		}
		return new TcpConnection(tcp);
	}

	/**
		The address of the peer, such as `127.0.0.1:50123`.
	**/
	public function peerName() {
		return switch (tcp.getPeerName()) {
			case Ok(address): '$address:${address.port}';
			case Error(_): "unknown";
		}
	}

	/**
		Suspends until data is available and returns it, or returns `null` once the peer has closed
		its side of the connection.
	**/
	@:coroutine public function read():Null<Bytes> {
		if (eof || closed) {
			return null;
		}
		return suspendCancellable(cont -> {
			tcp.readStart(result -> switch (result) {
				case Ok(buffer) if (buffer.size() == 0):
					// Zero-length reads don't mean anything, keep reading.
				case Ok(buffer):
					tcp.readStop();
					cont.resume(buffer.toBytes(), null);
				case Error(UV_EOF):
					tcp.readStop();
					eof = true;
					cont.resume(null, null);
				case Error(e):
					tcp.readStop();
					cont.resume(null, new LuvException(e));
			});
			_ -> {
				if (!closed) {
					tcp.readStop();
				}
			}
		});
	}

	/**
		Suspends until `bytes` have been written.
	**/
	@:coroutine public function write(bytes:Bytes) {
		if (closed) {
			throw new LuvException(UV_EPIPE);
		}
		suspend(cont -> {
			// On eval, `write` returns `null` instead of a `Result`, but errors are passed to the callback
			// as well.
			tcp.write([Buffer.fromBytes(bytes)], (result, _) -> switch (result) {
				case Ok(_):
					cont.resume(true, null);
				case Error(e):
					cont.resume(false, new LuvException(e));
			});
		});
	}

	/**
		Closes the connection. Has no effect if it is already closed.
	**/
	public function close() {
		if (!closed) {
			closed = true;
			tcp.close(() -> {});
		}
	}
}
