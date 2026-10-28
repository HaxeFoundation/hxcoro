package hxcoro.task.node;

import haxe.Exception;
import haxe.exceptions.CancellationException;

/**
	Strategy for scope tasks such as `Coro.scope`, which are cancelled when one of their children fails
	but not when a child is cancelled, and do not report their outcome to their parent.
**/
@:access(hxcoro.task.AbstractTask)
@:access(hxcoro.task.CoroTask)
class CoroScopeStrategy implements INodeStrategy {
	public function new() {}

	public function complete<T>(task:CoroBaseTask<T>) {
		task.parent?.childCompletes(task, false);
		task.handleAwaitingContinuations();
	}

	public function childSucceeds<T>(task:CoroBaseTask<T>, child:AbstractTask) {}

	public function childErrors<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:Exception) {
		switch (task.state.load()) {
			case Created | Running | Completing:
				// inherit child error
				task.doCancel(cause);
			case Cancelling | Completed | Cancelled:
		}
	}

	public function childCancels<T>(task:CoroBaseTask<T>, child:AbstractTask, cause:CancellationException) {}
}
