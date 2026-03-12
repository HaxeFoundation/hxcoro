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

	static function deepEquals(a:Dynamic, b:Dynamic):Bool {
		if (a == b) return true;
		if (a == null || b == null) return false;

		return switch (Type.typeof(a)) {
			case TInt, TFloat:
				switch (Type.typeof(b)) {
					case TInt, TFloat: (a : Float) == (b : Float);
					case _: false;
				}
			case TBool: a == b;
			case TClass(c):
				if (c == Array) {
					final arrA:Array<Dynamic> = a;
					final arrB:Array<Dynamic> = b;
					if (arrB == null || arrA.length != arrB.length) return false;
					for (i in 0...arrA.length)
						if (!deepEquals(arrA[i], arrB[i])) return false;
					true;
				} else if (c == String) {
					(a : String) == (b : String);
				} else {
					// Class instances: compare fields
					final fields = Type.getInstanceFields(c);
					for (field in fields) {
						final va = Reflect.getProperty(a, field);
						if (Reflect.isFunction(va)) continue;
						final vb = Reflect.getProperty(b, field);
						if (!deepEquals(va, vb)) return false;
					}
					true;
				}
			case TEnum(_):
				switch (Type.typeof(b)) {
					case TEnum(_):
						if (Type.enumIndex(a) != Type.enumIndex(b)) return false;
						final paramsA = Type.enumParameters(a);
						final paramsB = Type.enumParameters(b);
						if (paramsA.length != paramsB.length) return false;
						for (i in 0...paramsA.length)
							if (!deepEquals(paramsA[i], paramsB[i])) return false;
						true;
					case _: false;
				}
			case TObject:
				// Anonymous objects
				final fieldsA = Reflect.fields(a);
				final fieldsB = Reflect.fields(b);
				if (fieldsA.length != fieldsB.length) return false;
				for (field in fieldsA)
					if (!deepEquals(Reflect.field(a, field), Reflect.field(b, field))) return false;
				true;
			case TFunction:
				Reflect.compareMethods(a, b);
			case _:
				false;
		}
	}
}
