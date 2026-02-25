import tests.FooBarBazTest;
import tests.TopRecursionTest;

function println(s:String) {
	#if sys
	Sys.println(s);
	#elseif js
	js.Syntax.code("console.log({0})", s);
	#else
	trace(s);
	#end
}

function exit(code:Int) {
	#if sys
	Sys.exit(code);
	#elseif js
	js.Syntax.code("process.exit({0})", code);
	#else
	throw 'exit $code';
	#end
}

function main() {
	final suite:Array<{name:String, run:() -> Void}> = [
		{name: "FooBarBaz", run: FooBarBazTest.run},
		{name: "TopRecursion", run: TopRecursionTest.run},
	];

	var passed = 0;
	var failed = 0;

	for (t in suite) {
		try {
			t.run();
			println('PASS ${t.name}');
			passed++;
		} catch (e:haxe.Exception) {
			println('FAIL ${t.name}');
			println(e.message);
			failed++;
		}
	}

	println('');
	println('Results: $passed passed, $failed failed');

	if (failed > 0)
		exit(1);
}

