package toprecursion;

function entry() {
	CoroRun.run(_ -> CoroLower.foo());
}
