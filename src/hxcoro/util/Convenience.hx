package hxcoro.util;

/**
	This module can be added via `using hxcoro.util.Convenience` in order to enable `using`
	functionality on all of hxcoro's static extension classes at once:

	- `hxcoro.util.ContinuationTools`
	- `hxcoro.util.ContextTools`
	- `hxcoro.util.DispatcherTools`
	- `hxcoro.task.ContextTasks`

	@see <https://haxe.org/manual/lf-static-extension.html>
**/
@:dox(hide)
typedef TContinuationTools = ContinuationTools;

@:dox(hide)
typedef TContextTools = ContextTools;

@:dox(hide)
typedef TDispatcherTools = DispatcherTools;

@:dox(hide)
typedef TContextTasks = hxcoro.task.ContextTasks;
