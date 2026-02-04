import yield.*;

function main() {

	var cases = [
		new TestBasic(),
		new TestTricky(),
		new TestControlFlow(),
		new TestTryCatch(),
		new TestHoisting(),
		new TestMisc(),
		new TestTexpr(),
		#if !hl
		new TestGenerator(),
		#end
		#if js
		new TestJsPromise(),
		#end
		#if false // need to run this single-threaded, but it depends on a hack in BaseContinuation...
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
	runner.addCases("run");
	runner.addCases("schedulers");
	runner.addCases("structured");

    utest.ui.Report.create(runner);
    runner.run();
}