package hxcoro.ds.channels;

import haxe.coro.AsyncIterator;
import hxcoro.ds.Out;
import hxcoro.generators.AsyncGenerator;

@:using(hxcoro.ds.channels.IChannelReader.ChannelReaderTools)
interface IChannelReader<T> {
	function tryRead(out:Out<T>):Bool;

	function tryPeek(out:Out<T>):Bool;

	@:coroutine function read():T;

	@:coroutine function waitForRead():Bool;
}

class ChannelReaderTools {
	static public function iterator<T>(reader:IChannelReader<T>) {
		return AsyncGenerator.create(yield -> {
			final out = new Out();
			while (reader.waitForRead()) {
				while (reader.tryRead(out)) {
					yield(out.get());
				}
			}
		});
	}
}