package hxcoro.ds.pipelines;

import haxe.io.ArrayBufferView;

interface IPipeWriter {
	function getBuffer(minimumSize:Int=0):ArrayBufferView;
	function advance(count:Int):Void;
	@:coroutine function flush():Void;
	function close():Void;
}