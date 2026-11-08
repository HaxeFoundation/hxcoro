package hxcoro.task;

import haxe.coro.context.Context;

/**
	The `Context` of a task as seen from its node. It is a plain `Context` that also offers the
	functions of `hxcoro.task.ContextTasks`, which create child tasks, without a `using` directive.

	The context's own `with` and `without` return a plain `Context`, so the elements of a child are
	best added in one call.
**/
@:using(hxcoro.task.ContextTasks)
typedef NodeContext = Context;
