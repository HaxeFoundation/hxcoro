package hxcoro.task;

/**
	Decides how a task relates to its parent: whether its own outcome is reported to the parent as
	a child outcome, and how the outcomes of its children affect it.
**/
enum abstract TaskKind(Int) {
	/**
		Reports its outcome to its parent, and is cancelled when one of its children fails or is
		cancelled.
	**/
	final Child;

	/**
		Does not report its outcome to its parent; whoever awaits the task receives it. Is cancelled
		when one of its children fails, but not when one is cancelled.
	**/
	final Scope;

	/**
		Like `Scope`, but the outcomes of its children are ignored.
	**/
	final Supervisor;
}
