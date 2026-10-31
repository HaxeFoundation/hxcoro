package json;

import haxe.io.ArrayBufferView;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import hxcoro.ds.Out;
import hxcoro.ds.channels.IChannelWriter;
import hxcoro.ds.pipelines.IPipeReader;
import json.Token;

/**
	Turns the UTF-8 bytes of a pipe into JSON tokens.

	The pipe delivers its data in chunks of arbitrary size, so a token can be split between two
	chunks. The lexer handles this without any buffering of its own: it lexes all complete tokens
	of the data it has, consumes them, and marks the remaining bytes as observed. The next read of
	the pipe then returns these bytes again, together with the newly arrived data, and the lexer
	starts over at the beginning of the incomplete token.
**/
class Lexer {
	/**
		Returned by the scan functions if a token may continue beyond the end of the data.
	**/
	static inline final INCOMPLETE = -1;

	/**
		Reads `input` until its writer is closed and writes the tokens to `output`. Writes `TEof`
		at the end and closes `output`.

		Throws `JsonException` on invalid input.
	**/
	@:coroutine static public function lex(input:IPipeReader, output:IChannelWriter<Token>) {
		final lexer = new Lexer(output);
		final out = new Out<ArrayBufferView>();
		// The position of the first unconsumed byte of the pipe.
		var position = 0;
		// The unconsumed bytes of the last read. These are needed after the writer is closed,
		// because `tryRead` doesn't return data again that was already fully observed.
		var rest:Null<ArrayBufferView> = null;

		while (input.waitForRead()) {
			while (input.tryRead(out)) {
				final data = out.get();
				final consumed = lexer.lexChunk(data, position, false);
				input.advance(consumed, data.byteLength - consumed);
				position += consumed;
				rest = consumed == data.byteLength ? null : data.sub(consumed);
			}
		}

		// There is no more data, so whatever is left must be complete.
		if (rest != null) {
			position += lexer.lexChunk(rest, position, true);
		}
		output.write({kind: TEof, position: position});
		output.close();
	}

	final output:IChannelWriter<Token>;

	// The chunk that is being lexed. The scan functions work with indices into `bytes`, from
	// the start of the chunk up to `end`.
	var bytes:Bytes;
	var end:Int;
	/**
		The difference between the position of a byte in the input and its index in `bytes`.
	**/
	var indexToPosition:Int;
	/**
		Whether the chunk ends with the input, or more data may follow.
	**/
	var isLast:Bool;

	/**
		The token found by the last call to `scanToken`, or `null` if there was none.
	**/
	var kind:Null<TokenKind>;
	var tokenStart:Int;

	function new(output:IChannelWriter<Token>) {
		this.output = output;
		this.bytes = Bytes.alloc(0);
		this.end = 0;
		this.indexToPosition = 0;
		this.isLast = false;
		this.kind = null;
		this.tokenStart = 0;
	}

	/**
		Lexes the complete tokens of `data`, which starts at `position` in the input, and writes
		them to `output`. Returns the number of bytes that were consumed.
	**/
	@:coroutine function lexChunk(data:ArrayBufferView, position:Int, isLast:Bool):Int {
		final start = data.byteOffset;
		bytes = data.buffer;
		end = start + data.byteLength;
		indexToPosition = position - start;
		this.isLast = isLast;

		var i = start;
		while (true) {
			final next = scanToken(i);
			if (next == INCOMPLETE) {
				break;
			}
			final kind = this.kind;
			if (kind == null) {
				// only whitespace was left
				i = next;
				break;
			}
			output.write({kind: kind, position: this.position(tokenStart)});
			i = next;
		}
		return i - start;
	}

	inline function position(i:Int) {
		return indexToPosition + i;
	}

	inline function byteAt(i:Int) {
		return i < end ? bytes.get(i) : -1;
	}

	/**
		Skips whitespace and scans the token at `i`. Returns the index after the token and
		stores it in `kind`. Returns the end of the data and sets `kind` to `null` if there is
		only whitespace left. Returns `INCOMPLETE` if the token may continue in the next chunk.
	**/
	function scanToken(i:Int):Int {
		while (i < end && isWhitespace(bytes.get(i))) {
			i++;
		}
		tokenStart = i;
		kind = null;
		if (i == end) {
			return end;
		}
		inline function punctuation(k:TokenKind) {
			kind = k;
			return i + 1;
		}
		return switch (bytes.get(i)) {
			case '{'.code: punctuation(TBraceOpen);
			case '}'.code: punctuation(TBraceClose);
			case '['.code: punctuation(TBracketOpen);
			case ']'.code: punctuation(TBracketClose);
			case ':'.code: punctuation(TColon);
			case ','.code: punctuation(TComma);
			case '"'.code: scanString(i);
			case 't'.code: scanKeyword(i, "true", TTrue);
			case 'f'.code: scanKeyword(i, "false", TFalse);
			case 'n'.code: scanKeyword(i, "null", TNull);
			case c if (c == '-'.code || isDigit(c)): scanNumber(i);
			case _: unexpected(i);
		}
	}

	function scanKeyword(start:Int, word:String, k:TokenKind):Int {
		for (j in 0...word.length) {
			if (byteAt(start + j) != StringTools.fastCodeAt(word, j)) {
				return unexpected(start + j);
			}
		}
		kind = k;
		return start + word.length;
	}

	function scanNumber(start:Int):Int {
		var i = start;
		if (byteAt(i) == '-'.code) {
			i++;
		}
		if (byteAt(i) == '0'.code) {
			i++;
			// JSON doesn't allow leading zeros
			if (isDigit(byteAt(i))) {
				return unexpected(i);
			}
		} else if (isDigit(byteAt(i))) {
			i = skipDigits(i);
		} else {
			return unexpected(i);
		}
		if (byteAt(i) == '.'.code) {
			i++;
			if (!isDigit(byteAt(i))) {
				return unexpected(i);
			}
			i = skipDigits(i);
		}
		if (byteAt(i) == 'e'.code || byteAt(i) == 'E'.code) {
			i++;
			if (byteAt(i) == '+'.code || byteAt(i) == '-'.code) {
				i++;
			}
			if (!isDigit(byteAt(i))) {
				return unexpected(i);
			}
			i = skipDigits(i);
		}
		// More digits may follow in the next chunk.
		if (i == end && !isLast) {
			return INCOMPLETE;
		}
		kind = TNumber(Std.parseFloat(bytes.getString(start, i - start)));
		return i;
	}

	function skipDigits(i:Int) {
		while (isDigit(byteAt(i))) {
			i++;
		}
		return i;
	}

	/**
		Strings are scanned in two passes: the first one only finds the closing quote, so that
		an incomplete string isn't decoded again for every chunk. The second one decodes it.
	**/
	function scanString(start:Int):Int {
		var i = start + 1;
		var hasEscapes = false;
		while (true) {
			if (i >= end) {
				return unexpected(end);
			}
			final c = bytes.get(i);
			if (c == '"'.code) {
				break;
			} else if (c == '\\'.code) {
				hasEscapes = true;
				i += 2;
			} else if (c < 0x20) {
				throw new JsonException("Control character in string", position(i));
			} else {
				i++;
			}
		}
		kind = TString(hasEscapes ? decodeString(start + 1, i) : bytes.getString(start + 1, i - start - 1));
		return i + 1;
	}

	/**
		Decodes the escape sequences of a string. The result is assembled as UTF-8 bytes, because
		`StringBuf.addChar` doesn't encode characters above 127 on targets with byte strings.
	**/
	function decodeString(start:Int, end:Int):String {
		final buf = new BytesBuffer();
		var runStart = start;
		var i = start;
		while (i < end) {
			if (bytes.get(i) != '\\'.code) {
				i++;
				continue;
			}
			buf.addBytes(bytes, runStart, i - runStart);
			switch (bytes.get(i + 1)) {
				case c = '"'.code | '\\'.code | '/'.code:
					buf.addByte(c);
				case 'b'.code:
					buf.addByte(8);
				case 'f'.code:
					buf.addByte(12);
				case 'n'.code:
					buf.addByte('\n'.code);
				case 'r'.code:
					buf.addByte('\r'.code);
				case 't'.code:
					buf.addByte('\t'.code);
				case 'u'.code:
					var code = readHex4(i + 2, end);
					i += 4;
					if (code >= 0xD800 && code < 0xDC00) {
						// a high surrogate, which should be followed by an escaped low surrogate
						final low = i + 8 <= end && bytes.get(i + 2) == '\\'.code && bytes.get(i + 3) == 'u'.code ? readHex4(i + 4, end) : -1;
						if (low >= 0xDC00 && low < 0xE000) {
							code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
							i += 6;
						} else {
							code = 0xFFFD;
						}
					} else if (code >= 0xDC00 && code < 0xE000) {
						code = 0xFFFD;
					}
					addUtf8(buf, code);
				case _:
					throw new JsonException("Invalid escape sequence", position(i));
			}
			i += 2;
			runStart = i;
		}
		buf.addBytes(bytes, runStart, end - runStart);
		return buf.getBytes().toString();
	}

	static function addUtf8(buf:BytesBuffer, code:Int) {
		if (code < 0x80) {
			buf.addByte(code);
		} else if (code < 0x800) {
			buf.addByte(0xC0 | (code >> 6));
			buf.addByte(0x80 | (code & 0x3F));
		} else if (code < 0x10000) {
			buf.addByte(0xE0 | (code >> 12));
			buf.addByte(0x80 | ((code >> 6) & 0x3F));
			buf.addByte(0x80 | (code & 0x3F));
		} else {
			buf.addByte(0xF0 | (code >> 18));
			buf.addByte(0x80 | ((code >> 12) & 0x3F));
			buf.addByte(0x80 | ((code >> 6) & 0x3F));
			buf.addByte(0x80 | (code & 0x3F));
		}
	}

	function readHex4(start:Int, end:Int):Int {
		if (start + 4 > end) {
			throw new JsonException("Invalid unicode escape sequence", position(start));
		}
		var code = 0;
		for (i in start...start + 4) {
			final c = bytes.get(i);
			final digit = if (isDigit(c)) {
				c - '0'.code;
			} else if (c >= 'a'.code && c <= 'f'.code) {
				c - 'a'.code + 10;
			} else if (c >= 'A'.code && c <= 'F'.code) {
				c - 'A'.code + 10;
			} else {
				throw new JsonException("Invalid unicode escape sequence", position(i));
			}
			code = (code << 4) | digit;
		}
		return code;
	}

	/**
		Handles an unexpected byte at `i`. If the data ended there, the token may continue in
		the next chunk, so this returns `INCOMPLETE`. Otherwise, it throws.
	**/
	function unexpected(i:Int):Int {
		if (i < end) {
			throw new JsonException('Unexpected character "${String.fromCharCode(bytes.get(i))}"', position(i));
		}
		if (isLast) {
			throw new JsonException("Unexpected end of input", position(end));
		}
		return INCOMPLETE;
	}

	static inline function isWhitespace(c:Int) {
		return c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code;
	}

	static inline function isDigit(c:Int) {
		return c >= '0'.code && c <= '9'.code;
	}
}
