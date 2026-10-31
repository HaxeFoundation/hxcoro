import Tcp.TcpConnection;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

using StringTools;

class ClientResponse {
	/**
		The status code, or 0 if the server closed the connection without responding.
	**/
	public final status:Int;

	public final headers:Map<String, String>;
	public final body:String;

	public function new(status:Int, headers:Map<String, String>, body:String) {
		this.status = status;
		this.headers = headers;
		this.body = body;
	}
}

/**
	A minimal HTTP client for the tests.
**/
class HttpClient {
	@:coroutine static public function get(port:Int, path:String) {
		return send(port, 'GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n');
	}

	/**
		Sends `raw` to the server and reads until it closes the connection.
	**/
	@:coroutine static public function send(port:Int, raw:String) {
		final connection = TcpConnection.connect("127.0.0.1", port);
		final buffer = new BytesBuffer();
		try {
			if (raw.length > 0) {
				connection.write(Bytes.ofString(raw));
			}
			while (true) {
				final chunk = connection.read();
				if (chunk == null) {
					break;
				}
				buffer.add(chunk);
			}
		} catch (e:haxe.Exception) {
			connection.close();
			throw e;
		}
		connection.close();
		return parse(buffer.getBytes().toString());
	}

	static function parse(data:String) {
		final headerEnd = data.indexOf("\r\n\r\n");
		if (headerEnd < 0) {
			return new ClientResponse(0, [], data);
		}
		final lines = data.substr(0, headerEnd).split("\r\n");
		final status = Std.parseInt(lines.shift().split(" ")[1]) ?? 0;
		final headers = new Map();
		for (line in lines) {
			final colon = line.indexOf(":");
			headers[line.substr(0, colon).toLowerCase()] = line.substr(colon + 1).trim();
		}
		return new ClientResponse(status, headers, data.substr(headerEnd + 4));
	}
}
