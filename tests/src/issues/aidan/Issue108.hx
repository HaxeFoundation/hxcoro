package issues.aidan;

class Issue108 extends atest.Test {
	public function testCast() {
		var a = [1];
		Assert.equals(1, run((_) -> {
			var v = cast if (a.length == 0) {
				null;
			} else {
				a.shift();
			};
			v;
		}));
	}

	public function testParenthesis() {
		var a = [1];
		Assert.equals(1, run((_) -> {
			var v = (if (a.length == 0) {
				null;
			} else {
				a.shift();
			});
			v;
		}));
	}

	public function testMetadata() {
		var a = [1];
		Assert.equals(1, run((_) -> {
			var v = @:myMeta if (a.length == 0) {
				null;
			} else {
				a.shift();
			};
			v;
		}));
	}
}