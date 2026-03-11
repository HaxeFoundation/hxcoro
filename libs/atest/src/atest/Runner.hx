package atest;

import haxe.atomic.AtomicInt;

/**
	Collects test cases, runs them and prints results.

	Each test method runs inside its own ``Coro.timeout`` scope,
	giving it a distinct coroutine task and enforcing the ``@:timeout``
	deadline.  A single event-loop / dispatcher is shared across all
	tests.

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
		// Thread-safe counters for future parallel execution.
		final totalTests = new AtomicInt(0);
		final totalPassed = new AtomicInt(0);
		final totalFailed = new AtomicInt(0);
		final totalErrors = new AtomicInt(0);
		// Sequential access only (coroutine is single-threaded).
		final failures:Array<String> = [];
		final cases = this.cases;

		final setup = hxcoro.run.Setup.createDefault();
		final context = setup.createContext();
		hxcoro.run.LoopRun.runTask(setup.loop, context, function(node) {
			for (c in cases) {
				println('${c.name}');
				final tests:Array<TestInfo> = (cast c.instance : Dynamic).__atestInit__();

				for (t in tests) {
					if (pattern != null && !StringTools.contains(t.name, pattern)) continue;

					totalTests.add(1);
					try {
						hxcoro.Coro.timeout(t.timeout, function(scopeNode) {
							c.instance.setup();
							t.execute(scopeNode);
							c.instance.teardown();
						});
						totalPassed.add(1);
						printResult(t.name, true, null);
					} catch (e:hxcoro.exceptions.TimeoutException) {
						totalFailed.add(1);
						final detail = 'timeout after ${t.timeout}ms';
						printResult(t.name, false, detail);
						failures.push('  ${c.name}::${t.name} - $detail');
					} catch (e:AssertFailure) {
						totalFailed.add(1);
						final detail = '${e.message} at ${e.posToString()}';
						printResult(t.name, false, detail);
						failures.push('  ${c.name}::${t.name} - $detail');
						try {
							c.instance.teardown();
						} catch (_:Dynamic) {}
					} catch (e:Dynamic) {
						totalErrors.add(1);
						final detail = Std.string(e);
						printResult(t.name, false, 'ERROR: $detail');
						failures.push('  ${c.name}::${t.name} - ERROR: $detail');
						try {
							c.instance.teardown();
						} catch (_:Dynamic) {}
					}
				}
			}
			return null;
		});
		setup.close();

		println("");
		if (failures.length > 0) {
			println("Failures:");
			for (f in failures) println(f);
			println("");
		}
		final passed = totalPassed.load();
		final failed = totalFailed.load();
		final errors = totalErrors.load();
		final total = totalTests.load();
		println('$total tests, $passed passed, $failed failed, $errors errors');
		return failed == 0 && errors == 0;
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
