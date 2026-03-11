package atest;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassType;

using Lambda;
#end

/**
	Build macro invoked by ``@:autoBuild`` on ``atest.Test``.
	Generates a ``__atestInit__`` method that returns an
	``Array<atest.TestInfo>`` describing every ``test*`` method.
**/
class TestBuilder {
	static inline var TEST_PREFIX = "test";
	static inline var TIMEOUT_META = ":timeout";
	static inline var DEFAULT_TIMEOUT = 10000;

	macro static public function build():Array<Field> {
		if (Context.defined("display")) return null;

		final cls = Context.getLocalClass().get();
		final fields = Context.getBuildFields();
		final isOverriding = ancestorHasAtestInit(cls);
		final initExprs:Array<Expr> = [];

		if (isOverriding) {
			initExprs.push(macro var tests = super.__atestInit__());
		} else {
			initExprs.push(macro var tests:Array<atest.TestInfo> = []);
		}

		for (field in fields) {
			switch (field.kind) {
				case FFun(fn):
					final isStatic = field.access != null && field.access.has(AStatic);
					if (!isStatic && StringTools.startsWith(field.name, TEST_PREFIX)) {
						final test = field.name;
						final timeoutExpr = getTimeoutExpr(cls, field);
						final isCoroutine = field.meta != null && field.meta.exists(m -> m.name == ":coroutine");

						if (isCoroutine) {
							initExprs.push(macro tests.push({
								name: $v{test},
								timeout: $timeoutExpr,
								execute: function() {
									atest.Runner.runCoro(function(_) {
										this.$test();
									});
								}
							}));
						} else {
							initExprs.push(macro tests.push({
								name: $v{test},
								timeout: $timeoutExpr,
								execute: function() {
									this.$test();
								}
							}));
						}
					}
				case _:
			}
		}

		initExprs.push(macro return tests);

		final initMethod = (macro class Dummy {
			@:noCompletion @:keep public function __atestInit__():Array<atest.TestInfo>
				$b{initExprs}
		}).fields[0];

		if (isOverriding) {
			initMethod.access.push(AOverride);
		}

		fields.push(initMethod);
		return fields;
	}

#if macro
	static function ancestorHasAtestInit(cls:ClassType):Bool {
		if (cls.superClass == null) return false;
		final superClass = cls.superClass.t.get();
		for (field in superClass.fields.get()) {
			if (field.name == "__atestInit__") return true;
		}
		return ancestorHasAtestInit(superClass);
	}

	static function getTimeoutExpr(cls:ClassType, field:Field):Expr {
		if (field.meta != null) {
			for (m in field.meta) {
				if (m.name == TIMEOUT_META && m.params != null && m.params.length == 1) {
					return m.params[0];
				}
			}
		}
		if (cls.meta.has(TIMEOUT_META)) {
			final metas = cls.meta.extract(TIMEOUT_META);
			if (metas.length > 0 && metas[0].params != null && metas[0].params.length == 1) {
				return metas[0].params[0];
			}
		}
		return macro $v{DEFAULT_TIMEOUT};
	}
#end
}
