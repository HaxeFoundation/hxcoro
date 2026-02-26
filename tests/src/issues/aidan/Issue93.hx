package issues.aidan;

@:coroutine function doSomethingUsefulOne() {
	return 13;
}

@:coroutine function doSomethingUsefulTwo() {
	return 29;
}

@:coroutine function doSomethingUsefulOneYield() {
	yield();
	return 13;
}

@:coroutine function doSomethingUsefulTwoYield() {
	yield();
	return 29;
}

function sum(a:Int, b:Int) {
	return a + b;
}

function id(a:Int) {
	return a;
}

class Issue93 extends utest.Test {
	public function test() {
		Assert.equals(13, CoroRun.run((_) -> doSomethingUsefulOne()));
		Assert.equals(13, CoroRun.run((_) -> id(doSomethingUsefulOne())));
		Assert.equals(42, CoroRun.run((_) -> doSomethingUsefulOne() + doSomethingUsefulTwo()));
		Assert.equals(42, CoroRun.run((_) -> doSomethingUsefulOneYield() + doSomethingUsefulTwo()));
		Assert.equals(42, CoroRun.run((_) -> doSomethingUsefulOne() + doSomethingUsefulTwoYield()));
		Assert.equals(42, CoroRun.run((_) -> doSomethingUsefulOneYield() + doSomethingUsefulTwoYield()));
		Assert.equals(42, CoroRun.run((_) -> sum(doSomethingUsefulOne(), doSomethingUsefulTwo())));
		Assert.equals(42, CoroRun.run((_) -> sum(doSomethingUsefulOneYield(), doSomethingUsefulTwo())));
		Assert.equals(42, CoroRun.run((_) -> sum(doSomethingUsefulOne(), doSomethingUsefulTwoYield())));
		Assert.equals(42, CoroRun.run((_) -> sum(doSomethingUsefulOneYield(), doSomethingUsefulTwoYield())));
		Assert.equals(42, CoroRun.run((_) -> id(doSomethingUsefulOne() + doSomethingUsefulTwo())));
		Assert.equals(42, CoroRun.run((_) -> id(doSomethingUsefulOneYield() + doSomethingUsefulTwo())));
		Assert.equals(42, CoroRun.run((_) -> id(doSomethingUsefulOne() + doSomethingUsefulTwoYield())));
		Assert.equals(42, CoroRun.run((_) -> id(doSomethingUsefulOneYield() + doSomethingUsefulTwoYield())));
		Assert.equals(42, CoroRun.run((_) -> id(sum(doSomethingUsefulOne(), doSomethingUsefulTwo()))));
		Assert.equals(42, CoroRun.run((_) -> id(sum(doSomethingUsefulOneYield(), doSomethingUsefulTwo()))));
		Assert.equals(42, CoroRun.run((_) -> id(sum(doSomethingUsefulOne(), doSomethingUsefulTwoYield()))));
		Assert.equals(42, CoroRun.run((_) -> id(sum(doSomethingUsefulOneYield(), doSomethingUsefulTwoYield()))));
	}
}