package hxcoro.debug;

#if hxcoro.trace_tasks
import hxcoro.debug.TaskTrace.TaskTraceEvent;
import hxcoro.elements.CoroName;
import hxcoro.task.AbstractTask;
import hxcoro.task.CoroBaseTask;

/**
	Renders the events recorded by a `TaskTrace` as a Mermaid sequence diagram.

	Each task is a participant, named after its `CoroName` if it introduced one, and `scope of X`
	if it inherited the name of its parent `X`. Entering a method draws an arrow from the task whose
	method is currently running, or from the other task of the event, or from `code` if neither is
	known; leaving it ends the activation. State changes are notes.
**/
class SequenceDiagram {
	static public function render(events:Array<TaskTraceEvent>):String {
		final ids = new Map<Int, String>();
		final labels:Array<String> = [];
		function participant(task:AbstractTask):String {
			final id = ids.get(task.id);
			if (id != null) {
				return id;
			}
			final id = 'T${labels.length + 1}';
			ids.set(task.id, id);
			labels.push('participant $id as ${label(task)}');
			return id;
		}
		final lines:Array<String> = [];
		final stack:Array<AbstractTask> = [];
		var usesCode = false;
		for (event in events) {
			final target = participant(event.task);
			if (event.method == "state") {
				lines.push('Note over $target: ${event.info}');
				continue;
			}
			if (event.enter == false) {
				while (stack.length > 0 && stack.pop() != event.task) {}
				if (event.info != null) {
					lines.push('Note over $target: ${event.info}');
				}
				lines.push('deactivate $target');
				continue;
			}
			final other = event.other;
			final source = if (stack.length > 0) {
				participant(stack[stack.length - 1]);
			} else if (other != null) {
				participant(other);
			} else {
				usesCode = true;
				"code";
			}
			final text = event.info == null ? event.method : '${event.method}: ${event.info}';
			lines.push('$source->>$target: $text');
			if (event.enter == true) {
				lines.push('activate $target');
				stack.push(event.task);
			}
		}
		final header = ["sequenceDiagram"];
		if (usesCode) {
			header.push("participant code");
		}
		return header.concat(labels).concat(lines).map(line -> line == "sequenceDiagram" ? line : '    $line').join("\n");
	}

	static function label(task:AbstractTask):String {
		final coroTask = Std.downcast(task, CoroBaseTask);
		if (coroTask == null) {
			return 'task';
		}
		final name = coroTask.context.get(CoroName);
		if (name == null) {
			return 'task';
		}
		final parent = Std.downcast(@:privateAccess task.parent, CoroBaseTask);
		if (parent != null && parent.context.get(CoroName) == name) {
			return 'scope of ${name.name}';
		}
		return name.name;
	}
}
#end
