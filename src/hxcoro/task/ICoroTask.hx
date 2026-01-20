package hxcoro.task;

import haxe.coro.context.Context;
import haxe.Exception;
import haxe.exceptions.CancellationException;

interface ICoroTask<T> extends ILocalContext {
	var id(get, never):Int;
	var context(get, never):Context;
	function cancel(?cause:CancellationException):Void;
	@:coroutine function await():T;
	function get():T;
	function getError():Exception;
	function isActive():Bool;
	function onCompletion(callback:(result:T, error:Exception)->Void):Void;
}

interface IStartableCoroTask<T> extends ICoroTask<T> {
	function start():Void;
}
