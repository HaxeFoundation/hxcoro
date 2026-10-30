import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import sys.thread.Lock;
import sys.thread.Thread;

using StringTools;

/**
	Compiles and runs the Haxe examples of the hxcoro wiki. See README.md for the
	`<!-- test: ... -->` directives that control how code blocks are tested.
**/
typedef Block = {
	final lang:String;
	final code:String;
	final line:Int;
	final directives:Map<String, String>;
}

typedef RunResult = {
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
	final timedOut:Bool;
}

typedef Span = {
	final start:Int;
	final end:Int;
}

final timeoutSeconds = 30;
final directiveRegex = ~/^<!--\s*test:(.*?)-->$/;
final argRegex = ~/([\w-]+)(=("[^"]*"|\S+))?/;
final functionRegex = ~/^function\s+(\w+)/m;
final importRegex = ~/^(import|using)\s/;
final positionRegex = ~/^\S+?:\d+: /;

var srcPath = "";
var binPath = "";
var passed = 0;
var failed = 0;

function main() {
	final args = Sys.args();
	if (args.length != 1) {
		Sys.println("Usage: haxe --cwd wiki-tests --run WikiTests <path to wiki checkout>");
		Sys.exit(1);
	}
	final wikiPath = FileSystem.absolutePath(args[0]);
	srcPath = FileSystem.absolutePath("../src");
	binPath = FileSystem.absolutePath("bin");
	final pages = [for (file in FileSystem.readDirectory(wikiPath)) if (file.endsWith(".md")) file];
	pages.sort(Reflect.compare);
	for (page in pages) {
		testPage(page.substr(0, page.length - 3), File.getContent(Path.join([wikiPath, page])));
	}
	Sys.println('\nResults: $passed passed, $failed failed');
	Sys.exit(failed > 0 ? 1 : 0);
}

function pass(name:String) {
	Sys.println('PASS $name');
	passed++;
}

function fail(name:String, reason:String, ?result:RunResult) {
	Sys.println('FAIL $name');
	Sys.println(indent(reason.split("\n")));
	if (result != null) {
		final output = lines(result.stdout).concat(lines(result.stderr));
		if (output.length > 0) {
			Sys.println(indent(output.slice(0, 20)));
		}
	}
	failed++;
}

function indent(lines:Array<String>) {
	return [for (line in lines) '\t$line'].join("\n");
}

function lines(s:String) {
	return [for (line in s.replace("\r\n", "\n").split("\n")) if (line.trim() != "") line.rtrim()];
}

function parseBlocks(page:String, content:String):Array<Block> {
	final lines = content.replace("\r\n", "\n").split("\n");
	final blocks = [];
	var directives = new Map<String, String>();
	var directiveLine = 0;
	var i = 0;
	while (i < lines.length) {
		final line = lines[i].trim();
		if (directiveRegex.match(line)) {
			parseDirectives(directiveRegex.matched(1), directives);
			directiveLine = i + 1;
		} else if (line.startsWith("```")) {
			final start = i + 1;
			final code = [];
			i++;
			while (i < lines.length && !lines[i].trim().startsWith("```")) {
				code.push(lines[i]);
				i++;
			}
			blocks.push({
				lang: line.substr(3).trim(),
				code: code.join("\n"),
				line: start,
				directives: directives
			});
			directives = new Map();
		} else if (line != "" && directives.iterator().hasNext()) {
			fail('$page:$directiveLine', "directive is not directly followed by a code block");
			directives = new Map();
		}
		i++;
	}
	return blocks;
}

function parseDirectives(text:String, directives:Map<String, String>) {
	var rest = text;
	while (argRegex.match(rest)) {
		var value = argRegex.matched(2) == null ? "" : argRegex.matched(3);
		if (value.startsWith('"')) {
			value = value.substr(1, value.length - 2);
		}
		directives[argRegex.matched(1)] = value;
		rest = argRegex.matchedRight();
	}
}

function testPage(page:String, content:String) {
	final preludes = [];
	final modules = new Map<String, String>();
	final sources = new Map<String, String>();
	var last:Null<RunResult> = null;
	for (block in parseBlocks(page, content)) {
		final directives = block.directives;
		final name = '$page:${block.line}';
		if (block.lang != "haxe") {
			if (directives.exists("output")) {
				if (last == null) {
					fail(name, "output block without a preceding example");
				} else {
					checkOutput(name, last, block.code, directives["output"] == "nopos");
				}
			}
			continue;
		}
		if (directives.exists("skip")) {
			continue;
		}
		if (directives.exists("prelude")) {
			preludes.push(block.code);
			continue;
		}
		if (directives.exists("module")) {
			modules[directives["module"]] = block.code;
			continue;
		}
		var source = block.code;
		if (directives.exists("patch")) {
			final base = sources[directives["patch"]];
			if (base == null) {
				fail(name, 'unknown id "${directives["patch"]}"');
				continue;
			}
			source = patch(base, block.code);
		} else if (preludes.length > 0) {
			source = combine(preludes.concat([block.code]));
		}
		if (directives.exists("id")) {
			sources[directives["id"]] = source;
		}
		if (!findFunctions(source).exists("main")) {
			// Fragments are only tested if a directive says how
			if (directives.iterator().hasNext()) {
				fail(name, "block has no main function");
			}
			continue;
		}
		final result = run('$page-${block.line}', source, modules);
		last = result;
		if (directives.exists("error")) {
			final expected = directives["error"];
			if (result.exitCode != 0 && result.stderr.contains(expected)) {
				pass(name);
			} else {
				fail(name, 'expected a compilation error containing "$expected"', result);
			}
		} else if (result.timedOut) {
			fail(name, 'timed out after $timeoutSeconds seconds', result);
		} else if (result.exitCode != 0) {
			fail(name, 'exited with code ${result.exitCode}', result);
		} else {
			pass(name);
		}
	}
}

function checkOutput(name:String, result:RunResult, expected:String, noPositions:Bool) {
	final actual = [for (line in lines(result.stdout)) noPositions ? positionRegex.replace(line, "") : line];
	final expectedLines = lines(expected);
	if (actual.join("\n") == expectedLines.join("\n")) {
		pass(name);
	} else {
		fail(name, 'output mismatch\nexpected:\n${indent(expectedLines)}\nactual:\n${indent(actual)}');
	}
}

/**
	Combines several pieces of code into one module, moving all `import` and `using`
	declarations to the top.
**/
function combine(parts:Array<String>) {
	final imports = [];
	final body = [];
	for (part in parts) {
		for (line in part.split("\n")) {
			if (!importRegex.match(line)) {
				body.push(line);
			} else if (!imports.contains(line.trim())) {
				imports.push(line.trim());
			}
		}
		body.push("");
	}
	return imports.join("\n") + "\n\n" + body.join("\n");
}

/**
	Replaces the module-level functions of `base` with the ones of the same name in
	`code`, and adds the functions and imports that `base` doesn't have yet.
**/
function patch(base:String, code:String) {
	final codeFunctions = findFunctions(code);
	var result = base;
	for (name => span in codeFunctions) {
		final replacement = code.substring(span.start, span.end);
		final baseSpan = findFunctions(result)[name];
		result = if (baseSpan == null) {
			result + "\n\n" + replacement;
		} else {
			result.substr(0, baseSpan.start) + replacement + result.substr(baseSpan.end);
		}
	}
	final newImports = [for (line in code.split("\n")) if (importRegex.match(line) && !base.contains(line.trim())) line.trim()];
	return newImports.length == 0 ? result : newImports.join("\n") + "\n" + result;
}

/**
	Returns the spans of all functions declared at the start of a line in `source`.
**/
function findFunctions(source:String):Map<String, Span> {
	final functions = new Map();
	var pos = 0;
	while (functionRegex.matchSub(source, pos)) {
		final start = functionRegex.matchedPos().pos;
		var i = source.indexOf("{", start);
		var depth = 0;
		while (i < source.length) {
			switch (source.charCodeAt(i)) {
				case "{".code:
					depth++;
				case "}".code:
					depth--;
					if (depth == 0) {
						break;
					}
				case _:
			}
			i++;
		}
		functions[functionRegex.matched(1)] = {start: start, end: i + 1};
		pos = i + 1;
	}
	return functions;
}

function run(name:String, source:String, modules:Map<String, String>):RunResult {
	final dir = Path.join([binPath, name]);
	final sourceDir = Path.join([dir, "source"]);
	FileSystem.createDirectory(sourceDir);
	File.saveContent(Path.join([sourceDir, "Main.hx"]), source);
	for (module => code in modules) {
		File.saveContent(Path.join([sourceDir, '$module.hx']), code);
	}
	final process = new Process("haxe", ["--cwd", dir, "-cp", "source", "-cp", srcPath, "--main", "Main", "--interp"]);
	final lock = new Lock();
	var timedOut = false;
	Thread.create(() -> {
		if (!lock.wait(timeoutSeconds)) {
			timedOut = true;
			process.kill();
		}
	});
	final stdout = process.stdout.readAll().toString();
	final stderr = process.stderr.readAll().toString();
	final exitCode = process.exitCode();
	lock.release();
	process.close();
	return {
		exitCode: exitCode,
		stdout: stdout,
		stderr: stderr,
		timedOut: timedOut
	};
}
