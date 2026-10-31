# Streaming JSON parser

A JSON parser that reads bytes from a `Pipe` and writes each value to a `Channel` as soon as it is complete. It shows how pipes and channels connect the stages of a pipeline:

```
bytes ──Pipe──▶ Lexer ──Channel<Token>──▶ Parser ──Channel<JsonValue>──▶ consumer
```

- [Lexer](src/json/Lexer.hx) reads chunks of bytes from an `IPipeReader` and writes tokens to a bounded channel. If a token is split between two chunks, the lexer consumes everything before it with `advance(consumed, observed)` and marks the rest as observed. The next read returns the start of the token again, together with the new data, so the lexer needs no buffer of its own.
- [Parser](src/json/Parser.hx) is a recursive descent parser whose functions are coroutines. It suspends whenever it needs a token that hasn't arrived yet. It only reads a token when it needs one, so a value is written as soon as its last token arrives, not when the next value begins.
- [JsonStream](src/json/JsonStream.hx) runs both in a `scope`. If one of them throws a `JsonException`, the other one is cancelled.

The input is a sequence of JSON values separated by whitespace, such as [JSON Lines](https://jsonlines.org/) or a single document.

```haxe
CoroRun.run(node -> {
	final pipe = Pipe.create();
	final values:Channel<JsonValue> = Channel.createBounded({size: 16});
	node.async(_ -> JsonStream.parse(pipe.reader, values.writer));
	node.async(_ -> {
		pipe.writer.write(Bytes.ofString('{"id": 1}\n{"id": 2}\n'));
		pipe.writer.close();
	});
	for (value in values.reader) {
		trace(value); // the object with id 1, then the object with id 2
	}
});
```

Limitations, compared with a production parser:

- Numbers are parsed as `Float`, so large integers lose precision.
- A token that is split between chunks is lexed again from its start, and the pipe copies the unconsumed bytes when new data arrives. A very long string that arrives in many small chunks therefore takes quadratic time.
- A number at the very end of the data can only be completed once the next byte arrives or the pipe is closed, because more digits could follow.
- There is no nesting limit, so deeply nested input can exhaust the stack.

See [test/TestJson.hx](test/TestJson.hx) for more examples. The tests feed every input in all chunk sizes, so every token is split at every possible point.
