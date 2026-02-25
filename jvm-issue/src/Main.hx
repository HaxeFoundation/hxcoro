// Expected output:
//   Running A
//   Running B
//   Running C
//
// Actual output on JVM:
//   Running C
//   Running C
//   Running C
//
// Root cause: the JVM backend generates a single shared closure class for
// static method references that share the same simple class+method name
// (here: `Test.run` from packages a, b and c).  The closure class is named
// after the *last* reference encountered in codegen, so every entry in the
// array ends up calling c.Test.run.

function main() {
	final cases:Array<{name:String, run:() -> Void}> = [
		{name: "a", run: a.Test.run},
		{name: "b", run: b.Test.run},
		{name: "c", run: c.Test.run},
	];

	for (c in cases) {
		Sys.print('${c.name}: ');
		c.run();
	}
}
