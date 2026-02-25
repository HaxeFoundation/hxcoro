package;

import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Macro that browses the `cases` directory and returns an array literal of
	`{ name: String, run: () -> Void }` entries for every subdirectory that
	contains a `Test.hx` file.  Convention: each test case lives in its own
	directory under `cases/` and exposes a static `run()` method via a class
	named `Test` in the matching package.
**/
class CaseMacro {
	macro public static function discoverCases():Expr {
		final casesDir = "cases";
		final entries:Array<Expr> = [];

		for (name in sys.FileSystem.readDirectory(casesDir)) {
			final dir = '$casesDir/$name';
			if (sys.FileSystem.isDirectory(dir) && sys.FileSystem.exists('$dir/Test.hx')) {
				entries.push(macro {name: $v{name}, run: $p{[name, "Test"]}.run});
			}
		}

		return macro $a{entries};
	}
}
