#if !target.threaded
#error "The thread tests need a threaded target"
#end

function main() {
	final runner = new atest.Runner();
	atest.Macros.addCases(runner, "cases");
	Sys.exit(runner.run() ? 0 : 1);
}
