import hxcoro.run.Setup;

function main() {
	#if sys
	switch (Sys.getEnv("HXCORO_DISPATCHER")) {
		case "trampoline":
			Sys.println("Using trampoline dispatcher");
			TestRun.setupFactory = Setup.createEventLoopTrampoline;
		#if target.threaded
		case "threadpool":
			Sys.println("Using threadpool dispatcher");
			TestRun.setupFactory = () -> Setup.createThreadPool(10);
		#end
		case _:
			Sys.println("Using default dispatcher");
	}
	#end

	final runner = new atest.Runner();

	runner.addCase(new TestBasic());
	runner.addCase(new TestTricky());
	runner.addCase(new TestControlFlow());
	runner.addCase(new TestTryCatch());
	runner.addCase(new TestHoisting());
	runner.addCase(new TestTexpr());
	#if js
	runner.addCase(new TestJsPromise());
	#end

	atest.Macros.addCases(runner, "issues");
	atest.Macros.addCases(runner, "concurrent");
	atest.Macros.addCases(runner, "ds");
	atest.Macros.addCases(runner, "elements");
	atest.Macros.addCases(runner, "features");
	#if !hl // TODO: ping Yuxiao about this
	atest.Macros.addCases(runner, "generators");
	#end
	atest.Macros.addCases(runner, "run");
	atest.Macros.addCases(runner, "schedulers");
	atest.Macros.addCases(runner, "structured");

	final passed = runner.run();
	#if sys
	Sys.exit(passed ? 0 : 1);
	#end
}