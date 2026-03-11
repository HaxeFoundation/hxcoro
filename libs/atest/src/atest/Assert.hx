package atest;

import haxe.PosInfos;

/**
	Assertion methods for atest. On failure, each method throws an
	`AssertFailure` which is caught by the runner.
**/
class Assert {
	public static function pass(?msg:String, ?pos:PosInfos) {}

	public static function fail(?msg:String, ?pos:PosInfos) {
		throw new AssertFailure(msg != null ? msg : "Assertion failed", pos);
	}

	public static function isTrue(value:Bool, ?msg:String, ?pos:PosInfos) {
		if (!value) throw new AssertFailure(msg != null ? msg : "Expected true but was false", pos);
	}

	public static function isFalse(value:Bool, ?msg:String, ?pos:PosInfos) {
		if (value) throw new AssertFailure(msg != null ? msg : "Expected false but was true", pos);
	}

	public static function equals<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos) {
		if (expected != actual) {
			throw new AssertFailure(msg != null ? msg : 'Expected $expected but was $actual', pos);
		}
	}

	public static function notEquals<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos) {
		if (expected == actual) {
			throw new AssertFailure(msg != null ? msg : 'Expected not $expected but was $actual', pos);
		}
	}

	public static function isNull<T>(value:T, ?msg:String, ?pos:PosInfos) {
		if (value != null) {
			throw new AssertFailure(msg != null ? msg : 'Expected null but was $value', pos);
		}
	}

	public static function notNull<T>(value:T, ?msg:String, ?pos:PosInfos) {
		if (value == null) {
			throw new AssertFailure(msg != null ? msg : "Expected not null but was null", pos);
		}
	}

	public static function isOfType<T>(value:T, type:Any, ?msg:String, ?pos:PosInfos) {
		if (!Std.isOfType(value, type)) {
			final typeName = try Type.getClassName(type) catch (_:Dynamic) Std.string(type);
			final valueName = try Type.getClassName(Type.getClass(value)) catch (_:Dynamic) Std.string(value);
			throw new AssertFailure(
				msg != null ? msg : 'Expected type $typeName but was $valueName',
				pos
			);
		}
	}

	public static function raises(func:() -> Void, ?type:Any, ?msg:String, ?pos:PosInfos) {
		try {
			func();
		} catch (e:Dynamic) {
			if (type != null) {
				final ex:Dynamic = Std.isOfType(e, haxe.ValueException) ? (cast e : haxe.ValueException).value : e;
				if (!Std.isOfType(ex, type)) {
					throw new AssertFailure(
						msg != null ? msg : 'Expected exception of type ${Type.getClassName(type)} but got ${Type.getClassName(Type.getClass(ex))}',
						pos
					);
				}
			}
			return;
		}
		throw new AssertFailure(msg != null ? msg : "Expected exception but none was thrown", pos);
	}

	public static function same<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos) {
		if (!deepEquals(expected, actual)) {
			throw new AssertFailure(msg != null ? msg : 'Expected $expected but was $actual', pos);
		}
	}

	public static function contains<T>(match:T, values:Array<T>, ?msg:String, ?pos:PosInfos) {
		for (v in values) {
			if (deepEquals(match, v)) return;
		}
		throw new AssertFailure(msg != null ? msg : 'Array does not contain $match', pos);
	}

	public static function notContains<T>(match:T, values:Array<T>, ?msg:String, ?pos:PosInfos) {
		for (v in values) {
			if (deepEquals(match, v)) {
				throw new AssertFailure(msg != null ? msg : 'Array contains $match', pos);
			}
		}
	}

	static function deepEquals<T>(a:T, b:T):Bool {
		if (a == b) return true;
		if (a == null || b == null) return false;
		if (Std.isOfType(a, Array)) {
			final arrA:Array<Dynamic> = cast a;
			final arrB:Array<Dynamic> = cast b;
			if (arrA.length != arrB.length) return false;
			for (i in 0...arrA.length) {
				if (!deepEquals(arrA[i], arrB[i])) return false;
			}
			return true;
		}
		return false;
	}
}
