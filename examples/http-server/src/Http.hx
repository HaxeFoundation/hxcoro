import haxe.io.Bytes;
import Tcp.TcpConnection;

using StringTools;

/**
	Thrown by `HttpParser.readRequest` if a request is malformed.
**/
class BadRequestException extends haxe.Exception {}

/**
	An HTTP request.
**/
class Request {
	public final method:String;
	public final path:String;
	public final query:Map<String, String>;

	/**
		The request headers, with lower-case names.
	**/
	public final headers:Map<String, String>;

	public final body:String;

	public function new(method:String, path:String, query:Map<String, String>, headers:Map<String, String>, body:String) {
		this.method = method;
		this.path = path;
		this.query = query;
		this.headers = headers;
		this.body = body;
	}
}

/**
	An HTTP response.
**/
class Response {
	public final status:Int;
	public final headers:Map<String, String>;
	public final body:String;

	public function new(status:Int, body:String, ?headers:Map<String, String>) {
		this.status = status;
		this.body = body;
		this.headers = headers ?? new Map();
	}

	/**
		Creates a plain-text response.
	**/
	static public function text(status:Int, body:String) {
		return new Response(status, body, ["Content-Type" => "text/plain; charset=utf-8"]);
	}

	/**
		Serializes the response. Every response closes the connection, so there is no need to
		support keep-alive or chunked encoding.
	**/
	public function toBytes() {
		final body = Bytes.ofString(body);
		final head = new StringBuf();
		head.add('HTTP/1.1 $status ${reasonPhrase(status)}\r\n');
		for (name => value in headers) {
			head.add('$name: $value\r\n');
		}
		head.add('Content-Length: ${body.length}\r\n');
		head.add('Connection: close\r\n\r\n');
		return HttpParser.concat(Bytes.ofString(head.toString()), body);
	}

	static function reasonPhrase(status:Int) {
		return switch (status) {
			case 200: "OK";
			case 400: "Bad Request";
			case 404: "Not Found";
			case 500: "Internal Server Error";
			case 503: "Service Unavailable";
			case _: "Unknown";
		}
	}
}

/**
	A minimal HTTP/1.1 request parser. It supports `Content-Length` bodies, but not chunked
	encoding or keep-alive.
**/
class HttpParser {
	static inline final maxHeaderSize = 8192;
	static inline final maxBodySize = 1 << 20;

	/**
		Reads a request from `connection`. Returns `null` if the client closes the connection
		without sending anything.
	**/
	@:coroutine static public function readRequest(connection:TcpConnection):Null<Request> {
		var data = Bytes.alloc(0);
		var headerEnd = -1;
		while (headerEnd < 0) {
			final chunk = connection.read();
			if (chunk == null) {
				if (data.length == 0) {
					return null;
				}
				throw new BadRequestException("Incomplete request");
			}
			data = concat(data, chunk);
			headerEnd = findHeaderEnd(data);
			if (headerEnd < 0 && data.length > maxHeaderSize) {
				throw new BadRequestException("Headers too large");
			}
		}

		final lines = data.getString(0, headerEnd).split("\r\n");
		final requestLine = lines.shift().split(" ");
		if (requestLine.length != 3 || !requestLine[2].startsWith("HTTP/1.")) {
			throw new BadRequestException("Malformed request line");
		}
		final headers = new Map();
		for (line in lines) {
			final colon = line.indexOf(":");
			if (colon <= 0) {
				throw new BadRequestException("Malformed header");
			}
			headers[line.substr(0, colon).trim().toLowerCase()] = line.substr(colon + 1).trim();
		}

		final bodyStart = headerEnd + 4;
		final bodyLength = switch (headers["content-length"]) {
			case null:
				0;
			case value:
				final length = Std.parseInt(value);
				if (length == null || length < 0 || length > maxBodySize) {
					throw new BadRequestException("Invalid Content-Length");
				}
				length;
		}
		while (data.length < bodyStart + bodyLength) {
			final chunk = connection.read();
			if (chunk == null) {
				throw new BadRequestException("Incomplete body");
			}
			data = concat(data, chunk);
		}

		final target = requestLine[1];
		final queryStart = target.indexOf("?");
		final path = queryStart < 0 ? target : target.substr(0, queryStart);
		final query = new Map();
		if (queryStart >= 0) {
			for (pair in target.substr(queryStart + 1).split("&")) {
				final eq = pair.indexOf("=");
				if (eq < 0) {
					query[pair.urlDecode()] = "";
				} else {
					query[pair.substr(0, eq).urlDecode()] = pair.substr(eq + 1).urlDecode();
				}
			}
		}
		return new Request(requestLine[0], path, query, headers, data.getString(bodyStart, bodyLength));
	}

	static function findHeaderEnd(data:Bytes) {
		for (i in 0...data.length - 3) {
			if (data.get(i) == "\r".code && data.get(i + 1) == "\n".code && data.get(i + 2) == "\r".code && data.get(i + 3) == "\n".code) {
				return i;
			}
		}
		return -1;
	}

	static public function concat(a:Bytes, b:Bytes) {
		final result = Bytes.alloc(a.length + b.length);
		result.blit(0, a, 0, a.length);
		result.blit(a.length, b, 0, b.length);
		return result;
	}
}
