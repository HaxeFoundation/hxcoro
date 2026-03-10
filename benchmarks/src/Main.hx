import cases.BenchBasic;
import cases.BenchChannel;
import cases.BenchMutex;
import cases.BenchGenerator;
import cases.BenchTask;

/**
 * hxcoro benchmark suite entry point.
 *
 * Runs all benchmark cases, prints a human-readable table, saves results to
 * `results/latest.json` (relative to the working directory, which should be
 * the `benchmarks/` folder), and compares them against the previous run to
 * highlight regressions.
 *
 * Usage (from the repository root):
 *   haxe --cwd benchmarks build-<target>.hxml
 */

/** Deserialisation shape for a saved run. */
private typedef SavedRun = {
	var timestamp:Float;
	var target:String;
	var results:Array<BenchResult>;
}

function main() {
	final target = getTarget();
	say('=== hxcoro Benchmarks ===');
	say('Target: $target\n');

	// Load any previously saved results before overwriting them.
	#if sys
	final previous:Null<SavedRun> = loadPrevious(target);
	#end

	// Collect results from every benchmark module.
	final results:Array<BenchResult> = [];
	for (r in BenchBasic.run())     results.push(r);
	for (r in BenchTask.run())      results.push(r);
	for (r in BenchChannel.run())   results.push(r);
	for (r in BenchMutex.run())     results.push(r);
	for (r in BenchGenerator.run()) results.push(r);

	// Human-readable table.
	printTable(results);

	#if sys
	// Regression comparison and persistence.
	if (previous != null) {
		say('\nComparison with previous run (${previous.target}):');
		printComparison(results, previous.results);
	}
	saveResults(target, results);
	#end
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------

function say(s:String):Void {
	#if sys
	Sys.println(s);
	#elseif js
	js.Syntax.code("console.log({0})", s);
	#else
	trace(s);
	#end
}

function rpad(s:String, width:Int):String {
	while (s.length < width) s += ' ';
	return s;
}

function lpad(s:String, width:Int):String {
	while (s.length < width) s = ' ' + s;
	return s;
}

function fmtOps(ops:Float):String {
	final n = Math.round(ops);
	// Manually insert thousand separators.
	final s = Std.string(n);
	var out = '';
	for (i in 0...s.length) {
		final remaining = s.length - i;
		if (i > 0 && remaining % 3 == 0) out += ',';
		out += s.charAt(i);
	}
	return out;
}

function fmtMs(ms:Float):String {
	// Show one decimal place.
	final rounded = Math.round(ms * 10) / 10;
	return Std.string(rounded);
}

function printTable(results:Array<BenchResult>):Void {
	final COL1 = 26;
	final COL2 = 10;
	final COL3 = 13;
	final COL4 = 14;

	say(rpad('Benchmark', COL1) + lpad('Iter', COL2) + lpad('Time (ms)', COL3) + lpad('Ops/sec', COL4));
	say(StringTools.rpad('', '-', COL1 + COL2 + COL3 + COL4));
	for (r in results) {
		say(rpad(r.name, COL1)
			+ lpad(Std.string(r.iterations), COL2)
			+ lpad(fmtMs(r.elapsedMs), COL3)
			+ lpad(fmtOps(r.opsPerSec), COL4));
	}
}

// ---------------------------------------------------------------------------
// Regression comparison
// ---------------------------------------------------------------------------

/** Regression threshold: flag if current ops/sec is more than 10 % slower. */
final REGRESSION_THRESHOLD = 0.10;

function printComparison(current:Array<BenchResult>, previous:Array<BenchResult>):Void {
	final COL1 = 26;
	final COL2 = 14;
	final COL3 = 14;
	final COL4 = 10;

	say(rpad('Benchmark', COL1) + lpad('Previous', COL2) + lpad('Current', COL3) + lpad('Change', COL4));
	say(StringTools.rpad('', '-', COL1 + COL2 + COL3 + COL4));

	var regressions = 0;
	for (cur in current) {
		// Find the matching previous result by name.
		var prev:Null<BenchResult> = null;
		for (p in previous) {
			if (p.name == cur.name) { prev = p; break; }
		}
		if (prev == null) {
			say(rpad(cur.name, COL1) + lpad('N/A', COL2) + lpad(fmtOps(cur.opsPerSec), COL3) + lpad('new', COL4));
			continue;
		}

		final ratio   = (prev.opsPerSec > 0) ? cur.opsPerSec / prev.opsPerSec : 1.0;
		final pct     = Math.round((ratio - 1.0) * 1000) / 10; // one decimal place
		final sign    = pct >= 0 ? '+' : '';
		final flag    = (ratio < 1.0 - REGRESSION_THRESHOLD) ? ' ⚠' : '';
		final change  = '$sign${pct}%$flag';

		if (flag != '') regressions++;

		say(rpad(cur.name, COL1)
			+ lpad(fmtOps(prev.opsPerSec), COL2)
			+ lpad(fmtOps(cur.opsPerSec), COL3)
			+ lpad(change, COL4));
	}

	if (regressions > 0)
		say('\n⚠  $regressions benchmark(s) regressed by more than ${Std.int(REGRESSION_THRESHOLD * 100)}%.');
}

// ---------------------------------------------------------------------------
// JSON persistence  (sys targets only)
// ---------------------------------------------------------------------------

#if sys

final RESULTS_DIR = 'results';

function resultsFile(target:String):String {
	return 'results/latest-$target.json';
}

function loadPrevious(target:String):Null<SavedRun> {
	final file = resultsFile(target);
	if (!sys.FileSystem.exists(file)) return null;
	try {
		final content = sys.io.File.getContent(file);
		return haxe.Json.parse(content);
	} catch (_:Any) {
		return null;
	}
}

function saveResults(target:String, results:Array<BenchResult>):Void {
	final run:SavedRun = {
		timestamp: Date.now().getTime(),
		target:    target,
		results:   results,
	};
	final json = haxe.Json.stringify(run, null, '  ');
	final file = resultsFile(target);
	try {
		if (!sys.FileSystem.exists(RESULTS_DIR))
			sys.FileSystem.createDirectory(RESULTS_DIR);
		sys.io.File.saveContent(file, json);
		say('\nResults saved to $file');
	} catch (e:Any) {
		say('\nWarning: could not save results – $e');
	}
}

#end

// ---------------------------------------------------------------------------
// Target identification
// ---------------------------------------------------------------------------

function getTarget():String {
	#if eval   return "eval";
	#elseif cpp   return "cpp";
	#elseif jvm   return "jvm";
	#elseif hl    return "hl";
	#elseif js    return "js";
	#elseif python return "python";
	#elseif php   return "php";
	#elseif neko  return "neko";
	#else         return "unknown";
	#end
}
