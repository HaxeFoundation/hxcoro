package issues.aidan;

function someCall(v:Dynamic) {}

class Issue79 extends atest.Test {
	function test() {
		run(function(_) {
			someCall({
				var a = 1;
				someCall(a);
				a;
			});
		});
		Assert.pass();
	}
}