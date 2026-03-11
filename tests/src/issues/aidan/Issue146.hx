package issues.aidan;

class Issue146 extends atest.Test {
	function test() {
		run(_ -> {
			Assert.equals("time is 123456", 'time is ${123456i64}');
		});
	}
}