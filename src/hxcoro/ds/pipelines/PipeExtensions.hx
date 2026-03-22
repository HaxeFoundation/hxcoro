package hxcoro.ds.pipelines;

import haxe.io.Bytes;

class PipeExtensions {
	@:coroutine public static function write(writer:IPipeWriter, bytes:Bytes) {
		final buffer = writer.getBuffer(bytes.length);
		buffer.buffer.blit(buffer.byteOffset, bytes, 0, bytes.length);
		writer.advance(bytes.length);
		writer.flush();
	}
}