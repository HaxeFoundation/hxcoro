package hxcoro.ds.pipelines;

import haxe.io.Bytes;

/**
	Static extensions for `IPipeWriter`.
**/
class PipeExtensions {
	/**
		Writes all of `bytes` to `writer` and flushes it.
	**/
	@:coroutine public static function write(writer:IPipeWriter, bytes:Bytes) {
		final buffer = writer.getBuffer(bytes.length);
		buffer.buffer.blit(buffer.byteOffset, bytes, 0, bytes.length);
		writer.advance(bytes.length);
		writer.flush();
	}
}