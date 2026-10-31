function main() {
	final runner = new atest.Runner();
	runner.addCase(new TestJson());
	final passed = runner.run();
	#if sys
	Sys.exit(passed ? 0 : 1);
	#end
}
