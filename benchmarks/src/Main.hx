import cases.BenchWorkerPool;
import cases.BenchPipeline;
import cases.BenchContendedMutex;
import cases.BenchCancellation;
import cases.BenchFanOut;
import cases.BenchGenerator;

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
	for (r in BenchWorkerPool.run())      results.push(r);
	for (r in BenchPipeline.run())        results.push(r);
	for (r in BenchContendedMutex.run())  results.push(r);
	for (r in BenchCancellation.run())    results.push(r);
	for (r in BenchFanOut.run())          results.push(r);
	for (r in BenchGenerator.run())       results.push(r);

	// Print combined results table (with Change column when a baseline exists).
	#if sys
	printTable(results, previous?.results);
	saveResults(target, results);
	#else
	printTable(results, null);
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

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

/** Regression threshold: flag if current ops/sec is more than 10 % slower. */
final REGRESSION_THRESHOLD = 0.10;

/**
 * Print the benchmark results table.
 *
 * When `previous` is non-null a "Change" column is appended to every row
 * and regression warnings are printed at the end.
 */
function printTable(results:Array<BenchResult>, previous:Null<Array<BenchResult>>):Void {
	final COL1 = 28;
	final COL2 = 13; // Time (ms)
	final COL3 = 14; // Ops/sec
	final COL4 = 10; // Change

	final havePrev = previous != null;
	say(rpad('Benchmark', COL1)
		+ lpad('Time (ms)', COL2)
		+ lpad('Ops/sec', COL3)
		+ (havePrev ? lpad('Change', COL4) : ''));
	say(StringTools.rpad('', '-', COL1 + COL2 + COL3 + (havePrev ? COL4 : 0)));

	var regressions = 0;
	for (r in results) {
		var changeStr = '';
		if (havePrev) {
			var prev:Null<BenchResult> = null;
			for (p in previous) if (p.name == r.name) { prev = p; break; }
			changeStr = if (prev == null) {
				lpad('new', COL4);
			} else {
				final ratio = (prev.opsPerSec > 0) ? r.opsPerSec / prev.opsPerSec : 1.0;
				final pct   = Math.round((ratio - 1.0) * 1000) / 10;
				final sign  = pct >= 0 ? '+' : '';
				final flag  = (ratio < 1.0 - REGRESSION_THRESHOLD) ? ' ⚠' : '';
				if (flag != '') regressions++;
				lpad('$sign${pct}%$flag', COL4);
			};
		}
		say(rpad(r.name, COL1)
			+ lpad(fmtMs(r.elapsedMs), COL2)
			+ lpad(fmtOps(r.opsPerSec), COL3)
			+ changeStr);
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
