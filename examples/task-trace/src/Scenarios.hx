import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.exceptions.CancellationException;
import hxcoro.debug.SequenceDiagram;
import hxcoro.debug.TaskTrace;
import hxcoro.elements.CoroName;
import hxcoro.elements.NonCancellable;

typedef Scenario = {
	final title:String;
	final description:String;
	final run:(trace:TaskTrace) -> Void;
}

/**
	Small task trees whose lifecycle is worth looking at. `renderAll` runs them with tracing on and
	returns a Markdown document with one sequence diagram per scenario.
**/
class Scenarios {
	@:coroutine static function awaitCancellation() {
		suspendCancellable((_:IContinuation<Any>) -> null);
	}

	static public final all:Array<Scenario> = [
		{
			title: "A child completes",
			description: "The root creates a child that yields once and returns a value, and awaits it.",
			run: trace -> VirtualRun.run(trace, node -> {
				final child = node.with(new CoroName("child")).async(_ -> {
					yield();
					42;
				});
				child.await();
			})
		},
		{
			title: "A child is cancelled",
			description: "The root creates a child that waits for cancellation, cancels it, and awaits it.",
			run: trace -> VirtualRun.run(trace, node -> {
				final child = node.with(new CoroName("child")).async(_ -> awaitCancellation());
				yield();
				child.cancel();
				try {
					child.await();
				} catch (_:CancellationException) {}
			})
		},
		{
			title: "A child fails",
			description: "Under a supervisor, a parent creates a child that throws, and awaits it. The failure is reported to the parent while the child is still winding down, and the parent's cancellation interrupts the await.",
			run: trace -> VirtualRun.run(trace, node -> {
				supervisor(s -> {
					final parent = s.with(new CoroName("parent")).async(p -> {
						final child = p.with(new CoroName("child")).async(_ -> {
							yield();
							throw new Exception("boom");
						});
						child.await();
					});
					try {
						parent.await();
					} catch (_:Exception) {}
				});
			})
		},
		{
			title: "A NonCancellable cleanup block",
			description: "A cancelled child runs a cleanup block in a `NonCancellable` scope before it rethrows. The parent's cancellation does not reach the block.",
			run: trace -> VirtualRun.run(trace, node -> {
				final child = node.with(new CoroName("child")).async(n -> {
					try {
						awaitCancellation();
					} catch (e:CancellationException) {
						n.with(new NonCancellable(), new CoroName("cleanup")).scope(_ -> yield());
						throw e;
					}
				});
				yield();
				child.cancel();
				try {
					child.await();
				} catch (_:CancellationException) {}
			})
		},
	];

	static public function record(scenario:Scenario):Array<TaskTraceEvent> {
		final events = [];
		scenario.run(new TaskTrace(event -> events.push(event)));
		return events;
	}

	static public function renderAll():String {
		final out = [
			"# Task lifecycles",
			"",
			"Sequence diagrams of the lifecycle method calls of hxcoro tasks, recorded with `hxcoro.debug.TaskTrace` and rendered with `hxcoro.debug.SequenceDiagram`. Regenerate this file with `haxe --cwd examples/task-trace build-eval.hxml`.",
			"",
			"An arrow is a method call on the target task, from the task whose method or body is running, or from `outside` when none is. A bar is the time a method is active, or the time a body runs after a suspension (`run`). A note is a state change or the result of a method.",
			"",
		];
		for (scenario in Scenarios.all) {
			out.push('## ${scenario.title}');
			out.push("");
			out.push(scenario.description);
			out.push("");
			out.push("```mermaid");
			out.push(SequenceDiagram.render(record(scenario)));
			out.push("```");
			out.push("");
		}
		return out.join("\n");
	}
}
