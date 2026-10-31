package json;

import hxcoro.Coro.*;
import hxcoro.ds.channels.Channel;
import hxcoro.ds.channels.IChannelWriter;
import hxcoro.ds.pipelines.IPipeReader;
import json.Token;

/**
	Parses JSON from a pipe, connecting `Lexer` and `Parser` with a channel of tokens.
**/
class JsonStream {
	/**
		Reads a sequence of JSON values from `input` until its writer is closed, and writes each
		value to `output` as soon as it is complete. Closes `output` at the end.

		The lexer and the parser run concurrently. The token channel between them is bounded, so
		the lexer suspends if it gets too far ahead of the parser. If either of them throws, the
		other one is cancelled and the exception is rethrown.

		Throws `JsonException` on invalid input.
	**/
	@:coroutine static public function parse(input:IPipeReader, output:IChannelWriter<JsonValue>) {
		final tokens:Channel<Token> = Channel.createBounded({size: 16});
		scope(node -> {
			node.async(_ -> Lexer.lex(input, tokens.writer));
			Parser.parse(tokens.reader, output);
		});
	}
}
