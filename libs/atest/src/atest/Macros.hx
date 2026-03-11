package atest;

/**
	Compile-time helpers. Kept in a separate class to avoid loading
	runtime-only hxcoro types during macro processing.
**/
class Macros {
	/** Embed the value of a ``-D`` define as a compile-time constant. **/
	public static macro function getDefine(name:haxe.macro.Expr):haxe.macro.Expr {
		final str = switch (name.expr) {
			case EConst(CString(s, _)): s;
			default: null;
		};
		if (str == null) return macro null;
		final val = haxe.macro.Context.definedValue(str);
		return val != null ? macro $v{val} : macro null;
	}
}
