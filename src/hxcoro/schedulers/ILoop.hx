package hxcoro.schedulers;

enum abstract LoopMode(Int) {
	final Default;
	final Once;
	final NoWait;
}

interface ILoop {
	function loop(loopMode:LoopMode):Int;
}