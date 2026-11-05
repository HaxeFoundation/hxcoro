# Task trace

Sequence diagrams of what a task does over its lifetime, generated from the code rather than drawn by hand.

With `-D hxcoro.trace_tasks`, the task classes report every lifecycle method call to `hxcoro.task.TaskTrace`: creation, activation, the own work finishing or failing, cancellation requests, state changes, children starting and completing, awaiters being resumed. Without the define, the calls compile to nothing.

- `src/Scenarios.hx` holds small task trees worth looking at and runs them on a virtual clock, so the recorded order is deterministic.
- `src/SequenceDiagram.hx` turns a recording into a [Mermaid](https://mermaid.js.org/syntax/sequenceDiagram.html) sequence diagram: tasks are participants, a method call is an arrow from the task whose method is running, a bar is the time a method is active, and state changes are notes.
- [diagrams.md](diagrams.md) is the result, one diagram per scenario. GitHub renders it. The test regenerates it and fails if it was out of date, so it stays current with the library.

```bash
haxe --cwd examples/task-trace build-eval.hxml
```

To look at a situation of your own, add a scenario to `Scenarios.all`, or record one directly:

```haxe
final events = [];
TaskTrace.start(event -> events.push(event));
// run some tasks
TaskTrace.stop();
Sys.println(SequenceDiagram.render(events));
```
