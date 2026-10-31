package json;

import hxcoro.ds.channels.IChannelReader;
import hxcoro.ds.channels.IChannelWriter;
import json.JsonValue;
import json.Token;

/**
	Turns JSON tokens into JSON values.

	This is a plain recursive descent parser with one token of lookahead. Its functions are
	coroutines, so whenever it needs a token that the lexer hasn't produced yet, it suspends
	until the token arrives.
**/
class Parser {
	/**
		Reads a sequence of JSON values from `input` and writes each one to `output` as soon as
		it is complete. Closes `output` after `TEof`.

		The values can be separated by whitespace, as in [JSON Lines](https://jsonlines.org/).
		A single JSON document is a sequence of one value.

		Throws `JsonException` on invalid input.
	**/
	@:coroutine static public function parse(input:IChannelReader<Token>, output:IChannelWriter<JsonValue>) {
		final parser = new Parser(input);
		while (!parser.peek().kind.match(TEof)) {
			output.write(parser.parseValue());
		}
		output.close();
	}

	final input:IChannelReader<Token>;
	/**
		The next token, or `null` if it hasn't been read yet.
	**/
	var token:Null<Token>;

	function new(input:IChannelReader<Token>) {
		this.input = input;
		this.token = null;
	}

	/**
		Returns the next token without consuming it.

		The token is only read when it is needed, so that a value is complete as soon as its
		last token arrives. Otherwise, the parser would wait for the next value to begin before
		it could return this one.

		The lexer always ends with `TEof`, so this never reads from a closed channel.
	**/
	@:coroutine function peek():Token {
		final current = token;
		if (current != null) {
			return current;
		}
		final next = input.read();
		token = next;
		return next;
	}

	/**
		Consumes the token returned by the last `peek`.
	**/
	function advance() {
		token = null;
	}

	/**
		Consumes the next token if it is of kind `kind`, and throws otherwise.
	**/
	@:coroutine function expect(kind:TokenKind) {
		if (!Type.enumEq(peek().kind, kind)) {
			unexpected();
		}
		advance();
	}

	@:coroutine function parseValue():JsonValue {
		final value = switch (peek().kind) {
			case TNull: JNull;
			case TTrue: JBool(true);
			case TFalse: JBool(false);
			case TNumber(n): JNumber(n);
			case TString(s): JString(s);
			case TBracketOpen:
				advance();
				return parseArray();
			case TBraceOpen:
				advance();
				return parseObject();
			case _: unexpected();
		}
		advance();
		return value;
	}

	@:coroutine function parseArray():JsonValue {
		final values = [];
		if (peek().kind.match(TBracketClose)) {
			advance();
			return JArray(values);
		}
		while (true) {
			values.push(parseValue());
			switch (peek().kind) {
				case TComma:
					advance();
				case TBracketClose:
					advance();
					return JArray(values);
				case _:
					unexpected();
			}
		}
	}

	@:coroutine function parseObject():JsonValue {
		final fields:Array<JsonField> = [];
		if (peek().kind.match(TBraceClose)) {
			advance();
			return JObject(fields);
		}
		while (true) {
			final name = switch (peek().kind) {
				case TString(s): s;
				case _: unexpected();
			}
			advance();
			expect(TColon);
			fields.push({name: name, value: parseValue()});
			switch (peek().kind) {
				case TComma:
					advance();
				case TBraceClose:
					advance();
					return JObject(fields);
				case _:
					unexpected();
			}
		}
	}

	/**
		Throws an error about the token returned by the last `peek`.
	**/
	function unexpected<T>():T {
		final token = this.token;
		if (token == null) {
			throw "unexpected() must be called after peek()";
		}
		throw new JsonException(token.kind.match(TEof) ? "Unexpected end of input" : 'Unexpected ${token.kind}', token.position);
	}
}
