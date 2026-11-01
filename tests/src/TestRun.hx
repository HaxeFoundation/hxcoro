import hxcoro.run.Setup;
import hxcoro.run.LoopRun;
import hxcoro.task.NodeLambda;
import hxcoro.task.CoroBaseTask;
import haxe.coro.IContinuation;

var setupFactory:() -> hxcoro.run.Setup.LoopSetup = Setup.createDefault;

function run<T>(lambda:NodeLambda<T>#if coro.stack_traces, ?callPos:haxe.PosInfos#end):T {
	final s = setupFactory();
	final context = s.createContext();
	#if target.threaded
	final watched = Watchdog.watch(s);
	final task = LoopRun.runTask(s.loop, context, node -> {
		watched.setRootTask(node.context.get(CoroBaseTask));
		return lambda(node);
	}#if coro.stack_traces, callPos#end);
	#else
	final task = LoopRun.runTask(s.loop, context, lambda#if coro.stack_traces, callPos#end);
	#end
	s.close();
	#if target.threaded
	Watchdog.unwatch();
	#end
	return switch (task.getError()) {
		case null: task.get();
		case error: throw error;
	};
}

/**
	Suspends until the current task is cancelled, then throws the `CancellationException`.

	Use this instead of a long `delay` to wait for cancellation, so that the test doesn't depend
	on the timing of a real-time scheduler.
**/
@:coroutine function awaitCancellation() {
	hxcoro.Coro.suspendCancellable((_:IContinuation<Any>) -> null);
}
