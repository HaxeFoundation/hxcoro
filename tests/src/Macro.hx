import haxe.Timer;
import sys.FileSystem;

function autoRunCpp() {
	haxe.macro.Context.onAfterGenerate(() -> {
		runCommand(FileSystem.fullPath("bin/cpp/Main-debug"));
	});
}

class CommandFailure extends haxe.Exception {
	public final exitCode:Int;
	public function new(exitCode:Int = 1) {
		super("Command failed: " + Std.string(exitCode));
		this.exitCode = exitCode;
	}
}

final systemName = Sys.systemName();
final isGithub = Sys.getEnv("GITHUB_ACTIONS") == "true";
final colorSupported = switch [isGithub, systemName] {
	case [true, _]: true;
	case [_, "Linux" | "Mac"]: true;
	case [_, "Windows"]: false;
	case _: false;
}

function successMsg(msg:String):Void {
	Sys.println(colorSupported ? '\x1b[32m' + msg + '\x1b[0m' : msg);
}

function failMsg(msg:String):Void {
	Sys.println(colorSupported ? '\x1b[31m' + msg + '\x1b[0m' : msg);
}

function infoMsg(msg:String):Void {
	Sys.println(colorSupported ? '\x1b[36m' + msg + '\x1b[0m' : msg);
}

function getDisplayCmd(cmd:String, ?args:Array<String>) {
	return cmd + (args == null ? '' : ' $args');
}

/**
	Run a command using `Sys.command()`.
	If the command exits with non-zero code, throws `CommandFailure` with the same code.
*/
function runCommand(cmd:String, ?args:Array<String>):Void {
	final exitCode = showAndRunCommand(cmd, args);

	if (exitCode != 0)
		throw new CommandFailure(exitCode);
}

function showAndRunCommand(cmd:String, args:Null<Array<String>>, ?displayed:String):Int {
	if (displayed == null)
		displayed = getDisplayCmd(cmd, args);

	infoMsg('Command: $displayed');

	final t = Timer.stamp();
	final exitCode = Sys.command(cmd, args);
	final dt = Math.round(Timer.stamp() - t);

	final msg = 'Command exited with $exitCode in ${dt}s: $displayed';
	if (exitCode != 0)
		failMsg(msg);
	else
		successMsg(msg);

	return exitCode;
}
