import sys.FileSystem;

function autoRunCpp() {
	haxe.macro.Context.onAfterGenerate(() -> {
		#if debug
		final exe = FileSystem.fullPath("bin/cpp/Main-debug");
		#else
		final exe = FileSystem.fullPath("bin/cpp/Main");
		#end
		final exitCode = Sys.command(exe);
		if (exitCode != 0) {
			Sys.exit(exitCode);
		}
	});
}
