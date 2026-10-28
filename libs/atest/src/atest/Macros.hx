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

	/**
		Discover all ``.hx`` files in ``pkg`` (relative to the first
		``--class-path`` that contains the package directory) and generate
		``runner.addCase(new full.package.ClassName())`` calls for each one.
	**/
	public static macro function addCases(runner:haxe.macro.Expr, pkg:haxe.macro.Expr):haxe.macro.Expr {
		final pkgStr = switch (pkg.expr) {
			case EConst(CString(s, _)): s;
			default:
				haxe.macro.Context.error("Expected string literal", pkg.pos);
				return macro {};
		};
		final relDir = StringTools.replace(pkgStr, ".", "/");
		// Search all class paths for the package directory.
		var dir:String = null;
		for (cp in haxe.macro.Context.getClassPath()) {
			final candidate = (cp == "" ? "" : (cp + "/")) + relDir;
			if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate)) {
				dir = candidate;
				break;
			}
		}
		if (dir == null) {
			haxe.macro.Context.error('Package directory not found: $relDir', pkg.pos);
			return macro {};
		}

		final exprs:Array<haxe.macro.Expr> = [];
		function scan(currentDir:String, currentPkg:String) {
			for (entry in sys.FileSystem.readDirectory(currentDir)) {
				final full = currentDir + "/" + entry;
				if (sys.FileSystem.isDirectory(full)) {
					scan(full, currentPkg + "." + entry);
				} else if (StringTools.endsWith(entry, ".hx")) {
					final className = entry.substr(0, entry.length - 3);
					final tp:haxe.macro.Expr.TypePath = {
						pack: currentPkg.split("."),
						name: className,
					};
					exprs.push({expr: haxe.macro.Expr.ExprDef.ECall(macro $runner.addCase, [{
						expr: haxe.macro.Expr.ExprDef.ENew(tp, []),
						pos: pkg.pos,
					}]), pos: pkg.pos});
				}
			}
		}
		scan(dir, pkgStr);
		return macro $b{exprs};
	}
}
