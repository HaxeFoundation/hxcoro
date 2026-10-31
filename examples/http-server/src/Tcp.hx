import SelectScheduler;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Error;
import sys.net.Host;
import sys.net.Socket;

/**
	A TCP socket that listens for incoming connections.

	It can only be used from coroutines whose dispatcher uses a `SelectScheduler`.
**/
class TcpListener {
	/**
		The port the listener is bound to, which is useful when binding to port 0.
	**/
	public final port:Int;

	final scheduler:SelectScheduler;
	final socket:Socket;
	var closed = false;

	function new(scheduler:SelectScheduler, socket:Socket) {
		this.scheduler = scheduler;
		this.socket = socket;
		port = socket.host().port;
	}

	/**
		Creates a listener bound to `host` and `port`.
	**/
	@:coroutine static public function bind(host:String, port:Int) {
		final scheduler = SelectScheduler.current();
		final socket = new Socket();
		try {
			socket.bind(new Host(host), port);
			socket.listen(128);
			socket.setBlocking(false);
		} catch (e:haxe.Exception) {
			socket.close();
			throw e;
		}
		return new TcpListener(scheduler, socket);
	}

	/**
		Suspends until a client connects and returns the connection, or returns `null` once the
		listener has been closed.
	**/
	@:coroutine public function accept():Null<TcpConnection> {
		while (!closed) {
			if (!scheduler.wait(socket, Readable)) {
				return null;
			}
			final client = tryAccept();
			if (client != null) {
				return new TcpConnection(scheduler, client);
			}
		}
		return null;
	}

	function tryAccept() {
		try {
			final client = socket.accept();
			client.setBlocking(false);
			return client;
		} catch (e:Error) {
			switch (e) {
				case Blocked:
					return null;
				case _:
					throw e;
			}
		}
	}

	/**
		Stops listening. A pending `accept` call returns `null`.
	**/
	public function close() {
		if (!closed) {
			closed = true;
			scheduler.abort(socket);
			socket.close();
		}
	}
}

/**
	A connected TCP socket.
**/
class TcpConnection {
	final scheduler:SelectScheduler;
	final socket:Socket;
	final buffer = Bytes.alloc(16384);
	var eof = false;
	var closed = false;

	public function new(scheduler:SelectScheduler, socket:Socket) {
		this.scheduler = scheduler;
		this.socket = socket;
	}

	/**
		Connects to `host` and `port`. Connecting blocks, which is fine for the loopback connections
		of the tests.
	**/
	@:coroutine static public function connect(host:String, port:Int) {
		final scheduler = SelectScheduler.current();
		final socket = new Socket();
		try {
			socket.connect(new Host(host), port);
			socket.setBlocking(false);
		} catch (e:haxe.Exception) {
			socket.close();
			throw e;
		}
		return new TcpConnection(scheduler, socket);
	}

	/**
		The address of the peer, such as `127.0.0.1:50123`.
	**/
	public function peerName() {
		try {
			final peer = socket.peer();
			return '${peer.host}:${peer.port}';
		} catch (e:haxe.Exception) {
			return "unknown";
		}
	}

	/**
		Suspends until data is available and returns it, or returns `null` once the peer has closed
		its side of the connection.
	**/
	@:coroutine public function read():Null<Bytes> {
		while (!eof && !closed) {
			if (!scheduler.wait(socket, Readable)) {
				return null;
			}
			final data = tryRead();
			if (data != null) {
				return data;
			}
		}
		return null;
	}

	function tryRead():Null<Bytes> {
		try {
			final length = socket.input.readBytes(buffer, 0, buffer.length);
			if (length > 0) {
				return buffer.sub(0, length);
			}
			// The socket was readable, so this is the end of the input.
			eof = true;
		} catch (e:Eof) {
			eof = true;
		} catch (e:Error) {
			switch (e) {
				case Blocked:
				case _:
					throw e;
			}
		}
		return null;
	}

	/**
		Suspends until `bytes` have been written.
	**/
	@:coroutine public function write(bytes:Bytes) {
		var pos = 0;
		while (true) {
			if (closed) {
				throw new Eof();
			}
			pos += tryWrite(bytes, pos);
			if (pos == bytes.length) {
				return;
			}
			if (!scheduler.wait(socket, Writable)) {
				throw new Eof();
			}
		}
	}

	function tryWrite(bytes:Bytes, pos:Int) {
		try {
			return socket.output.writeBytes(bytes, pos, bytes.length - pos);
		} catch (e:Error) {
			switch (e) {
				case Blocked:
					return 0;
				case _:
					throw e;
			}
		}
	}

	/**
		Closes the connection. Has no effect if it is already closed.
	**/
	public function close() {
		if (!closed) {
			closed = true;
			scheduler.abort(socket);
			socket.close();
		}
	}
}
