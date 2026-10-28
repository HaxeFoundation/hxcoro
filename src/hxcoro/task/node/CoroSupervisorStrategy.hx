package hxcoro.task.node;

import haxe.Exception;
import haxe.exceptions.CancellationException;

/**
	Strategy for `Coro.supervisor` tasks, which ignore the outcome of their children and do not report
	their outcome to their parent.
**/
@:access(hxcoro.task.AbstractTask)
@:access(hxcoro.task.CoroBaseTask)
class CoroSupervisorStrategy implements INodeStrategy {
	public function new() {}

	public function complete<T>(task:CoroBaseTask<T>) {
		task.parent?.childCompletes(task, false);
		task.handleAwaitingContinuations();
	}

	public function childSucceeds<T>(task:CoroBaseTask<T>, child:AbstractTask) {}

	public function childErrors<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:Exception) {}

	public function childCancels<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:CancellationException) {}
}
