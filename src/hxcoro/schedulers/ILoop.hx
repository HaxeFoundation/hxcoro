package hxcoro.schedulers;

enum abstract RunMode(Int) {
	final Once = 1;
	final NoWait = 2;
}

interface ILoop {
	function loop(runMode:RunMode):Void;
	function wakeUp():Void;
}