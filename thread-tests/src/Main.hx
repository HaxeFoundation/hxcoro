#if !target.threaded
#error "The thread tests need a threaded target"
#end

function main() {
	final runner = new atest.Runner();
	#if hxcoro_known_failures
	// Tests for known bugs from the 1.0 review. They are expected to fail, so they only run
	// with `-D hxcoro-known-failures`, in a CI job that doesn't fail the workflow. Once a bug
	// is fixed, its test moves to `cases`.
	atest.Macros.addCases(runner, "review");
	#else
	atest.Macros.addCases(runner, "cases");
	#end
	Sys.exit(runner.run() ? 0 : 1);
}
