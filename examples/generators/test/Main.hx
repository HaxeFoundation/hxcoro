function main() {
	final runner = new atest.Runner();
	runner.addCase(new TestGenerator());
	runner.addCase(new TestAsyncGenerator());
	final passed = runner.run();
	#if sys
	Sys.exit(passed ? 0 : 1);
	#end
}
