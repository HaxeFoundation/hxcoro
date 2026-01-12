package hxcoro.task;

import haxe.coro.context.Context;
import haxe.coro.context.Key;

interface ILocalContext {
	var localContext(get, never):Null<AdjustableContext>;
}