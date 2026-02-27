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

	var cases = [
		new TestBasic(),
		new TestTricky(),
		new TestControlFlow(),
		new TestTryCatch(),
		new TestHoisting(),
		new TestTexpr(),
		#if js
		new TestJsPromise(),
		#end
	];

	var runner = new utest.Runner();

	for (eachCase in cases) {
		runner.addCase(eachCase);
	}
	runner.addCases("issues");
	runner.addCases("concurrent");
	runner.addCases("ds");
	runner.addCases("elements");
	runner.addCases("features");
	runner.addCases("generators");
	runner.addCases("run");
	runner.addCases("schedulers");
	runner.addCases("structured");

    utest.ui.Report.create(runner, NeverShowSuccessResults, AlwaysShowHeader);
    runner.run();
}