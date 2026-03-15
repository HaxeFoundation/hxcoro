import sys.FileSystem;

function autoRunCpp() {
	haxe.macro.Context.onAfterGenerate(() -> {
		#if debug
		final code = Sys.command(FileSystem.fullPath("bin/cpp/Main-debug"), []);
		#else
		final code = Sys.command(FileSystem.fullPath("bin/cpp/Main"), []);
		#end
		if (code != 0) Sys.exit(code);
	});
}
