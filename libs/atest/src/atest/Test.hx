package atest;

/**
	Base class for atest test cases. Extend this class and add public
	methods whose names start with ``test``. Both regular and
	``@:coroutine`` methods are supported.

	Override ``setup()`` / ``teardown()`` for per-test fixture code.
**/
@:keepSub
@:keep
@:autoBuild(atest.TestBuilder.build())
class Test {
	public function new() {}

	public function setup() {}

	public function teardown() {}
}
