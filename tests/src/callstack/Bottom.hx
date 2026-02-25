package callstack;

function entry() {
	CoroRun.run(_ -> CoroLower.foo());
}