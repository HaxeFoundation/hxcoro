package issues.aidan;

class Issue90 extends utest.Test {
	function testIf() {
		var val = "foo";
		function ret(value:String) {
			return value;
		}
		Assert.equals("foo", run((_) -> ret(val == null ? "null" : val)));
	}

	function testSwitch() {
		var val = "foo";
		function ret(value:String) {
			return value;
		}
		Assert.equals("foo", run((_) -> ret(switch(val) {
			case "bar": "bar";
			case "foo": "foo";
			case _: "_";
		})));
	}

	function testTry() {
		var val = "foo";
		function ret(value:String) {
			return value;
		}
		Assert.equals("foo", run((_) -> ret(try val catch(e:Dynamic) null)));
	}
}