import haxe.io.Bytes;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.pipelines.Pipe;
import json.JsonException;
import json.JsonStream;
import json.JsonValue;

using hxcoro.ds.pipelines.PipeExtensions;

class TestJson extends atest.Test {
	/**
		Parses `input` by writing it to a pipe in chunks of `chunkSize` bytes.
	**/
	static function parseChunked(input:String, chunkSize:Int):Array<JsonValue> {
		final bytes = Bytes.ofString(input);
		return run(node -> {
			final pipe = Pipe.create();
			final values:Channel<JsonValue> = Channel.createBounded({size: 4});
			node.async(_ -> {
				var i = 0;
				while (i < bytes.length) {
					final n = chunkSize < bytes.length - i ? chunkSize : bytes.length - i;
					pipe.writer.write(bytes.sub(i, n));
					i += n;
				}
				pipe.writer.close();
			});
			node.async(_ -> JsonStream.parse(pipe.reader, values.writer));
			[for (value in values.reader) value];
		});
	}

	/**
		Checks that `input` parses to `expected` for every chunk size, so that every token is
		split at every possible point.
	**/
	static function check(input:String, expected:Array<JsonValue>, ?pos:haxe.PosInfos) {
		for (chunkSize in 1...Bytes.ofString(input).length + 2) {
			Assert.same(expected, parseChunked(input, chunkSize), 'chunk size $chunkSize', pos);
		}
	}

	static function checkError(input:String, position:Int, ?pos:haxe.PosInfos) {
		for (chunkSize in 1...Bytes.ofString(input).length + 2) {
			final error = try {
				parseChunked(input, chunkSize);
				null;
			} catch (e:JsonException) {
				e;
			}
			if (Assert.notNull(error, 'chunk size $chunkSize', pos)) {
				Assert.equals(position, error.position, 'chunk size $chunkSize: ${error.message}', pos);
			}
		}
	}

	function testLiterals() {
		check("null", [JNull]);
		check("true", [JBool(true)]);
		check("false", [JBool(false)]);
	}

	function testNumbers() {
		check("0", [JNumber(0)]);
		check("-0", [JNumber(0)]);
		check("123", [JNumber(123)]);
		check("-1.5", [JNumber(-1.5)]);
		check("2e3", [JNumber(2000)]);
		check("2.5E-1", [JNumber(0.25)]);
		check("1e+2", [JNumber(100)]);
	}

	function testStrings() {
		check('""', [JString("")]);
		check('"hello"', [JString("hello")]);
		check('"a\\"b\\\\c\\/d"', [JString('a"b\\c/d')]);
		check('"\\b\\f\\n\\r\\t"', [JString("\x08\x0C\n\r\t")]);
		check('"\\u0041\\u00e9"', [JString("Aé")]);
		check('"\\ud83d\\ude00"', [JString("😀")]);
		// multi-byte UTF-8 characters, which are split between chunks
		check('"é😀"', [JString("é😀")]);
	}

	function testArrays() {
		check("[]", [JArray([])]);
		check("[1]", [JArray([JNumber(1)])]);
		check('[1, "two", [true, null], []]', [JArray([JNumber(1), JString("two"), JArray([JBool(true), JNull]), JArray([])])]);
	}

	function testObjects() {
		check("{}", [JObject([])]);
		check('{"a": 1}', [JObject([{name: "a", value: JNumber(1)}])]);
		check('{ "a" : { "b" : [ 1 , 2 ] } , "a" : null }', [
			JObject([
				{name: "a", value: JObject([{name: "b", value: JArray([JNumber(1), JNumber(2)])}])},
				{name: "a", value: JNull}
			])
		]);
	}

	function testSequence() {
		check("", []);
		check(" \t\r\n ", []);
		check("1 2 3", [JNumber(1), JNumber(2), JNumber(3)]);
		check('{"id": 1}\n{"id": 2}\n', [JObject([{name: "id", value: JNumber(1)}]), JObject([{name: "id", value: JNumber(2)}])]);
		check("[][]{}", [JArray([]), JArray([]), JObject([])]);
	}

	function testErrors() {
		checkError("x", 0);
		checkError("tru", 3);
		checkError("trux", 3);
		checkError("01", 1);
		checkError("-", 1);
		checkError("1.", 2);
		checkError("1e", 2);
		checkError('"abc', 4);
		checkError('"\\x"', 1);
		checkError('"\\u12"', 3);
		checkError("[1,]", 3);
		checkError("[1 2]", 3);
		checkError("[1", 2);
		checkError('{"a" 1}', 5);
		checkError("{1: 2}", 1);
		checkError('{"a": 1,}', 8);
	}

	/**
		Values are written to the output as soon as they are complete, so a consumer can react
		to them while the input is still being written.
	**/
	function testStreaming() {
		run(node -> {
			final pipe = Pipe.create();
			final values:Channel<JsonValue> = Channel.createBounded({size: 4});
			node.async(_ -> JsonStream.parse(pipe.reader, values.writer));

			pipe.writer.write(Bytes.ofString('{"a": 1}'));
			Assert.same(JObject([{name: "a", value: JNumber(1)}]), values.read());

			pipe.writer.write(Bytes.ofString(' [tr'));
			pipe.writer.write(Bytes.ofString('ue, "x"'));
			pipe.writer.write(Bytes.ofString(']'));
			Assert.same(JArray([JBool(true), JString("x")]), values.read());

			pipe.writer.close();
			Assert.isFalse(values.waitForRead());
		});
	}
}
