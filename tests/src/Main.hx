import hxcoro.run.Setup;

function main() {
	#if (sys && !lua_vanilla)
	switch (Sys.getEnv("HXCORO_DISPATCHER")) {
		case "trampoline":
			Sys.println("Using trampoline dispatcher");
			TestRun.setupFactory = Setup.createTrampoline;
		#if target.threaded
		case "threadpool":
			Sys.println("Using threadpool dispatcher");
			TestRun.setupFactory = () -> Setup.createThreadPool(10);
		#end
		case _:
			Sys.println("Using default dispatcher");
	}
	#end // (sys && !lua_vanilla)

	final runner = new atest.Runner();

	#if hxcoro_known_failures
	// Tests for known bugs from the 1.0 review. They are expected to fail, so they only run
	// with `-D hxcoro-known-failures`, in a CI job that doesn't fail the workflow. Once a bug
	// is fixed, its test moves to the matching package.
	atest.Macros.addCases(runner, "review");
	#else
	runner.addCase(new TestBasic());
	runner.addCase(new TestTricky());
	runner.addCase(new TestControlFlow());
	runner.addCase(new TestTryCatch());
	runner.addCase(new TestHoisting());
	runner.addCase(new TestTexpr());
	#if js
	// TODO: TestJsPromise needs conversion from utest.Async pattern to @:coroutine
	// runner.addCase(new TestJsPromise());
	#end

	atest.Macros.addCases(runner, "issues");
	atest.Macros.addCases(runner, "concurrent");
	atest.Macros.addCases(runner, "dispatchers");
	atest.Macros.addCases(runner, "ds");
	atest.Macros.addCases(runner, "elements");
	atest.Macros.addCases(runner, "features");
	atest.Macros.addCases(runner, "run");
	atest.Macros.addCases(runner, "schedulers");
	atest.Macros.addCases(runner, "structured");
	#end

	final passed = runner.run();
	#if sys
	Sys.exit(passed ? 0 : 1);
	#end
}