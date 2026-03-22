package hxcoro.ds.pipelines;

import haxe.io.ArrayBufferView;

interface IPipeReader {
	@:coroutine function waitForRead():Bool;
	function tryRead(out:Out<ArrayBufferView>):Bool;
	function tryReadAtLeast(count:Int, out:Out<ArrayBufferView>):Bool;
	function advance(consumed:Int, observed:Int):Void;
}