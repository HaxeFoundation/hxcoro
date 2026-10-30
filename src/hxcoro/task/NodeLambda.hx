package hxcoro.task;

import haxe.coro.Coroutine;

/**
	A coroutine executed by a task, receiving that task as its `ICoroNode` argument.
**/
typedef NodeLambda<T> = Coroutine<(node:ICoroNode) -> T>;
