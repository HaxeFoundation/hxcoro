import haxe.macro.Context;

/**
	Registers an `onAfterGenerate` hook that runs the compiled C++ binary.
	Mirrors the pattern used in `tests/src/Macro.hx:autoRunCpp()`.
**/
function run() {
	Context.onAfterGenerate(() -> {
		final binary = #if debug sys.FileSystem.fullPath("bin/cpp/Main-debug") #else sys.FileSystem.fullPath("bin/cpp/Main") #end;
		final exitCode = Sys.command(binary);
		if (exitCode != 0)
			throw new haxe.Exception('cpp binary exited with $exitCode: $binary');
	});
}
