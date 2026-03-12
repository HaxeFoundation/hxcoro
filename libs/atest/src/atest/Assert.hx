package atest;

import haxe.PosInfos;
import haxe.atomic.AtomicInt;

/**
	Assertion methods for atest. On failure, each method throws an
	`AssertFailure` which is caught by the runner. Methods return
	``true`` on success for use in conditional expressions.
**/
class Assert {
	/** Thread-safe assertion counter, incremented on every assertion call. **/
	public static final assertions = new AtomicInt(0);

	public static function pass(?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		return true;
	}

	public static function fail(?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		throw new AssertFailure(msg != null ? msg : "Assertion failed", pos);
	}

	public static function isTrue(value:Bool, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (!value) throw new AssertFailure(msg != null ? msg : "Expected true but was false", pos);
		return true;
	}

	public static function isFalse(value:Bool, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (value) throw new AssertFailure(msg != null ? msg : "Expected false but was true", pos);
		return true;
	}

	public static function equals<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (expected != actual) {
			throw new AssertFailure(msg != null ? msg : 'Expected $expected but was $actual', pos);
		}
		return true;
	}

	public static function notEquals<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (expected == actual) {
			throw new AssertFailure(msg != null ? msg : 'Expected not $expected but was $actual', pos);
		}
		return true;
	}

	public static function isNull<T>(value:T, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (value != null) {
			throw new AssertFailure(msg != null ? msg : 'Expected null but was $value', pos);
		}
		return true;
	}

	public static function notNull<T>(value:T, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (value == null) {
			throw new AssertFailure(msg != null ? msg : "Expected not null but was null", pos);
		}
		return true;
	}

	public static function isOfType<T>(value:T, type:Any, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (!Std.isOfType(value, type)) {
			final typeName = try Type.getClassName(type) catch (_:Dynamic) Std.string(type);
			final valueName = try Type.getClassName(Type.getClass(value)) catch (_:Dynamic) Std.string(value);
			throw new AssertFailure(
				msg != null ? msg : 'Expected type $typeName but was $valueName',
				pos
			);
		}
		return true;
	}

	public static function raises(func:() -> Void, ?type:Any, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
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
			return true;
		}
		throw new AssertFailure(msg != null ? msg : "Expected exception but none was thrown", pos);
	}

	public static function same<T>(expected:T, actual:T, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		if (!deepEquals(expected, actual)) {
			throw new AssertFailure(msg != null ? msg : 'Expected $expected but was $actual', pos);
		}
		return true;
	}

	public static function contains<T>(match:T, values:Array<T>, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		for (v in values) {
			if (deepEquals(match, v)) return true;
		}
		throw new AssertFailure(msg != null ? msg : 'Array does not contain $match', pos);
	}

	public static function notContains<T>(match:T, values:Array<T>, ?msg:String, ?pos:PosInfos):Bool {
		assertions.add(1);
		for (v in values) {
			if (deepEquals(match, v)) {
				throw new AssertFailure(msg != null ? msg : 'Array contains $match', pos);
			}
		}
		return true;
	}

	static function deepEquals<T>(a:T, b:T):Bool {
		if (a == b) return true;
		if (a == null || b == null) return false;
		// Arrays
		if (Std.isOfType(a, Array)) {
			final arrA:Array<Dynamic> = cast a;
			final arrB:Array<Dynamic> = cast b;
			if (arrA.length != arrB.length) return false;
			for (i in 0...arrA.length) {
				if (!deepEquals(arrA[i], arrB[i])) return false;
			}
			return true;
		}
		// Enum values – use Reflect.isEnumValue to avoid unsafe casts on C++.
		if (Reflect.isEnumValue(a)) {
			if (!Reflect.isEnumValue(b)) return false;
			final ea:EnumValue = cast a;
			final eb:EnumValue = cast b;
			if (Type.enumIndex(ea) != Type.enumIndex(eb)) return false;
			final paramsA = Type.enumParameters(ea);
			final paramsB = Type.enumParameters(eb);
			if (paramsA.length != paramsB.length) return false;
			for (i in 0...paramsA.length) {
				if (!deepEquals(paramsA[i], paramsB[i])) return false;
			}
			return true;
		}
		// Anonymous objects / structs
		if (Reflect.isObject(a) && Type.getClass(a) == null) {
			final fieldsA = Reflect.fields(a);
			final fieldsB = Reflect.fields(b);
			if (fieldsA.length != fieldsB.length) return false;
			for (field in fieldsA) {
				if (!deepEquals(Reflect.field(a, field), Reflect.field(b, field))) return false;
			}
			return true;
		}
		return false;
	}
}
