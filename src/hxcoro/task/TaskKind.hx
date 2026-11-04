package hxcoro.task;

/**
	Decides how a task relates to its parent: whether its own outcome is reported to the parent as
	a child outcome, and how the outcomes of its children affect it.
**/
enum abstract TaskKind(Int) {
	/**
		A task created by `async` or `lazy`. Its outcome is reported to its parent, and it is
		cancelled when one of its children fails or is cancelled.
	**/
	final Child;

	/**
		A task created by `Coro.scope` or `Coro.timeout`, or the root task of a run. Its outcome is
		not reported to its parent but to whoever awaits it, which for `Coro.scope` is the suspended
		caller. It is cancelled when one of its children fails, but not when one is cancelled.
	**/
	final Scope;

	/**
		A task created by `Coro.supervisor`. Like `Scope`, but the outcomes of its children are
		ignored.
	**/
	final Supervisor;
}
