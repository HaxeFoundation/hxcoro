package atest;

import haxe.atomic.AtomicInt;
import haxe.coro.context.IElement;

/**
	Collects test cases, runs them and prints results.

	Each test method runs inside its own ``Coro.timeout`` scope,
	giving it a distinct coroutine task and enforcing the ``@:timeout``
	deadline.  A single event-loop / dispatcher is shared across all
	tests.

	Context elements can be supplied at three levels (later levels
	take priority):
	  1. **Runner** – passed to the constructor.
	  2. **Class** – ``@:coroContext(…)`` metadata on the test class.
	  3. **Method** – ``@:coroContext(…)`` metadata on a ``test*`` method.

	Usage:
	```haxe
	final runner = new Runner();
	runner.addCase(new MyTests());
	Sys.exit(runner.run() ? 0 : 1);
	```
**/
class Runner {
	var cases:Array<CaseEntry> = [];
	var runnerContextElements:Array<IElement<Any>>;

	/**
		Create a new runner.

		@param contextElements  Context elements added to *every* test
		                        executed by this runner (lowest priority).
	**/
	public function new(...contextElements:IElement<Any>) {
		this.runnerContextElements = contextElements != null ? contextElements : [];
	}

	/**
		Register a test case instance.

		@param tc               The test case.
		@param contextElements  Extra context elements for every test in
		                        this case (between runner and class-level
		                        priority).
	**/
	public function addCase(tc:Test, ...contextElements:IElement<Any>) {
		final name = Type.getClassName(Type.getClass(tc));
		cases.push({name: name, instance: tc, contextElements: contextElements != null ? contextElements : []});
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
		final runnerCtx = this.runnerContextElements;

		// Use a single-threaded event loop for the runner itself.
		// Tests that need a thread pool create their own via run().
		final setup = hxcoro.run.Setup.createEventLoopTrampoline();
		final context = setup.createContext();
		hxcoro.run.LoopRun.runTask(setup.loop, context, function(node) {
			for (c in cases) {
				println('${c.name}');
				final tests:Array<TestInfo> = (cast c.instance : Dynamic).__atestInit__();

				for (t in tests) {
					if (pattern != null && !StringTools.contains(t.name, pattern)) continue;

					totalTests.add(1);
					printTestStart(t.name);
					try {
						// Extract `execute` into a local so the Lua backend
						// emits a plain function call instead of a colon-call
						// on the anonymous struct (which would shift args).
						final exec = t.execute;
						final beforeAssertions = Assert.assertions.load();

						// Merge context elements: runner → case → class/method.
						final testCtx = t.contextElements;
						final hasCtx = runnerCtx.length > 0 || c.contextElements.length > 0 || (testCtx != null && testCtx.length > 0);
						if (hasCtx) {
							// Run the timeout scope inside a scope with
							// the extra context elements applied.
							hxcoro.Coro.scope(function(scopeNode) {
								var ctx = scopeNode.context;
								for (e in runnerCtx) ctx = ctx.with(e);
								for (e in c.contextElements) ctx = ctx.with(e);
								if (testCtx != null) {
									for (e in testCtx) ctx = ctx.with(e);
								}
								hxcoro.util.Convenience.ContextConvenience.async(ctx, function(innerNode) {
									hxcoro.Coro.timeout(t.timeout, function(timeoutNode) {
										c.instance.setup();
										exec(timeoutNode);
										c.instance.teardown();
									});
									return null;
								}).await();
								return null;
							});
						} else {
							hxcoro.Coro.timeout(t.timeout, function(scopeNode) {
								c.instance.setup();
								exec(scopeNode);
								c.instance.teardown();
							});
						}
						if (Assert.assertions.load() == beforeAssertions) {
							throw new AssertFailure("No assertions made", null);
						}
						totalPassed.add(1);
						printTestEnd(true, null);
					} catch (e:hxcoro.exceptions.TimeoutException) {
						totalFailed.add(1);
						final detail = 'timeout after ${t.timeout}ms';
						printTestEnd(false, detail);
						failures.push('  ${c.name}::${t.name} - $detail');
					} catch (e:AssertFailure) {
						totalFailed.add(1);
						final detail = e.pos != null ? '${e.message} at ${e.posToString()}' : e.message;
						printTestEnd(false, detail);
						failures.push('  ${c.name}::${t.name} - $detail');
						try {
							c.instance.teardown();
						} catch (_:Dynamic) {}
					} catch (e:Dynamic) {
						totalErrors.add(1);
						final detail = Std.string(e);
						printTestEnd(false, 'ERROR: $detail');
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
		final assertionCount = Assert.assertions.load();
		println('$total tests, $passed passed, $failed failed, $errors errors, $assertionCount assertions');
		return failed == 0 && errors == 0;
	}

	// ------------------------------------------------------------------
	// Output helpers
	// ------------------------------------------------------------------

	static function printTestStart(name:String) {
		#if sys
		Sys.print('  $name ... ');
		Sys.stdout().flush();
		#elseif js
		js.Syntax.code("process.stdout.write('  ' + {0} + ' ... ')", name);
		#else
		trace('  $name ...');
		#end
	}

	static function printTestEnd(passed:Bool, ?detail:String) {
		#if sys
		Sys.println(passed ? 'OK' : 'FAIL: $detail');
		#elseif js
		js.Syntax.code("console.log({0})", passed ? 'OK' : 'FAIL: ' + detail);
		#else
		trace(passed ? 'OK' : 'FAIL: $detail');
		#end
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
	instance:Test,
	contextElements:Array<IElement<Any>>
}
