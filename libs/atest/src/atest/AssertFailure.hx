package atest;

/**
	Thrown by assertion methods when an assertion fails.
	The runner catches this to record test failures.
**/
class AssertFailure extends haxe.Exception {
	public final pos:Null<haxe.PosInfos>;

	public function new(msg:String, ?pos:haxe.PosInfos) {
		super(msg);
		this.pos = pos;
	}

	public function posToString():String {
		if (pos == null) return "unknown";
		return '${pos.fileName}:${pos.lineNumber}';
	}
}
