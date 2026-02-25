import yield.*;

function main() {

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
		#if debug
		new TestCallStack(),
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
	#if !hl // TODO: ping Yuxiao about this
	runner.addCases("generators");
	#end
	runner.addCases("run");
	runner.addCases("schedulers");
	runner.addCases("structured");

    utest.ui.Report.create(runner);
    runner.run();
}