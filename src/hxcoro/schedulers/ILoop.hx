package hxcoro.schedulers;

interface ILoop {
	function loop():Void;
	function wakeUp():Void;
}