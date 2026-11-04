package hxcoro.task;

/**
	Decides how a task relates to its parent, on two axes: whether it runs concurrently with its
	creator or in its place, which decides where its outcome goes, and whether a failing child
	fails it.
**/
enum abstract TaskKind(Int) {
	/**
		Runs beside its creator, which carries on, so a failure is reported to the parent. Its
		cancellation is not: it only concerns whoever awaits the task. Fails when a child fails.
	**/
	final Concurrent;

	/**
		Runs in place of its creator, which waits for it and receives the outcome. Fails when a
		child fails.
	**/
	final Sequential;

	/**
		Like `Sequential`, but a child's failure is left to whoever awaits the child.
	**/
	final SequentialSupervisor;
}
