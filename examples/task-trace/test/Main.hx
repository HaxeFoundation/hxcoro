function main() {
	final runner = new atest.Runner();
	runner.addCase(new TestTaskTrace());
	final passed = runner.run();
	Sys.exit(passed ? 0 : 1);
}
