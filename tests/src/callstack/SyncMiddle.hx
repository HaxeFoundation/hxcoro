package callstack;

function syncFun2() {
	CoroRun.run(_ -> CoroUpper.bar());
}

function syncFun1() {
	syncFun2();
}