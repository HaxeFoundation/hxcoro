package atest;

/**
	Collects test cases, runs them and prints results.

	Usage:
	```haxe
	final runner = new Runner();
	runner.addCase(new MyTests());
	Sys.exit(runner.run() ? 0 : 1);
	```
**/
class Runner {
	var cases:Array<CaseEntry> = [];

	public function new() {}

	/** Register a test case instance. **/
	public function addCase(tc:Test) {
		final name = Type.getClassName(Type.getClass(tc));
		cases.push({name: name, instance: tc});
	}

	/**
		Run all registered tests. Returns ``true`` when every test
		passes, ``false`` otherwise.
	**/
	public function run():Bool {
		final pattern = Macros.getDefine("ATEST-PATTERN");

		var totalTests = 0;
		var totalPassed = 0;
		var totalFailed = 0;
		var totalErrors = 0;
		var allPassed = true;
		final failures:Array<String> = [];

		for (c in cases) {
			println('${c.name}');
			final tests:Array<TestInfo> = (cast c.instance : Dynamic).__atestInit__();

			for (t in tests) {
				if (pattern != null && !StringTools.contains(t.name, pattern)) continue;

				totalTests++;
				c.instance.setup();
				try {
					t.execute();
					c.instance.teardown();
					totalPassed++;
					printResult(t.name, true, null);
				} catch (e:AssertFailure) {
					allPassed = false;
					totalFailed++;
					final detail = '${e.message} at ${e.posToString()}';
					printResult(t.name, false, detail);
					failures.push('  ${c.name}::${t.name} - $detail');
					try {
						c.instance.teardown();
					} catch (_:Dynamic) {}
				} catch (e:Dynamic) {
					allPassed = false;
					totalErrors++;
					final detail = Std.string(e);
					printResult(t.name, false, 'ERROR: $detail');
					failures.push('  ${c.name}::${t.name} - ERROR: $detail');
					try {
						c.instance.teardown();
					} catch (_:Dynamic) {}
				}
			}
		}

		println("");
		if (failures.length > 0) {
			println("Failures:");
			for (f in failures) println(f);
			println("");
		}
		println('$totalTests tests, $totalPassed passed, $totalFailed failed, $totalErrors errors');
		return allPassed;
	}

	// ------------------------------------------------------------------
	// Coroutine execution helper — uses fully qualified types to avoid
	// macro-time resolution of hxcoro imports.
	// ------------------------------------------------------------------

	/** Run a coroutine lambda synchronously using ``Setup.createDefault``. **/
	public static function runCoro<T>(lambda:hxcoro.task.NodeLambda<T>):T {
		final s = hxcoro.run.Setup.createDefault();
		final context = s.createContext();
		final task = hxcoro.run.LoopRun.runTask(s.loop, context, lambda);
		s.close();
		return switch (task.getError()) {
			case null: task.get();
			case error: throw error;
		};
	}

	// ------------------------------------------------------------------
	// Output helpers
	// ------------------------------------------------------------------

	static function printResult(name:String, passed:Bool, ?detail:String) {
		if (passed) {
			println('  $name ... OK');
		} else {
			println('  $name ... FAIL: $detail');
		}
	}

	static function println(msg:String) {
		#if sys
		Sys.println(msg);
		#elseif js
		js.Syntax.code("console.log({0})", msg);
		#else
		trace(msg);
		#end
	}
}

private typedef CaseEntry = {
	name:String,
	instance:Test
}
