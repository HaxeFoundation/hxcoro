package review;

import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.schedulers.ImmediateScheduler;

private class TestElement implements IElement<TestElement> {
	final key:Key<TestElement>;

	public final name:String;

	public function new(key:Key<TestElement>, name:String) {
		this.key = key;
		this.name = name;
	}

	public function getKey() {
		return key;
	}
}

/**
	Known failures from the 1.0 review: the coroutine transform of the Haxe compiler and the
	`haxe.coro` std runtime (items C*). The fixes go into the compiler repo,
	`src/coro/` and `std/haxe/coro/`, but the tests run here.

	Background on the transform:
	- `coroFromTexpr.ml` turns a typed function body into a graph of "coro blocks" (`cb`). Each
	  block has a `cb_next` (`NextSuspend`, `NextReturn`, `NextBreak`, ...) and a `cb_catch` that
	  points to the handler block.
	- `coroToTexpr.ml` turns blocks into numbered states of a `while(true) switch(gotoLabel)` state
	  machine, wrapped in a `try`. The exception handler (`eexchandle`) maps the current `gotoLabel`
	  to a catch state through `exc_state_map`.
	- Locals live across states as fields of the continuation ("hoisting"). They are restored at
	  the start of a state and saved at its end (`coroToTexpr.ml:249`).
	- `-D dump=pretty` writes the transform output to `dump/`.
**/
class TestCompiler extends atest.Test {
	static function thrower():Int {
		throw "boom";
	}

	/**
		C1: a throwing `return` expression inside a split `try` skips the catch.

		`src/coro/coroToTexpr.ml:509-510`:
		`| NextReturn e -> add_state (Some (-1)) [ set_control CoroReturned; b#assign eresult e; ereturn ] None`.
		`add_state` (`:473-480`) puts `set_state id`, i.e. `gotoLabel = -1`, before `extra_el`, so the
		result expression `e` is evaluated after `gotoLabel = -1`. If `e` throws, `eexchandle` switches
		on `-1`, finds no catch region and rethrows, so the coroutine completes as Thrown.
		`src/coro/coro.ml:609` `make_inline_return` has the same ordering.

		Fix: evaluate `e` first (assign `result = e` before `set_state (-1)`, or bind it to a temp),
		in both places.
	**/
	function testThrowingReturnInSplitTry() {
		@:coroutine function f():Int {
			try {
				yield();
				return thrower();
			} catch (e:Dynamic) {
				return -1;
			}
		}
		Assert.equals(-1, run(_ -> f()));
	}

	/**
		C1, nested variant: the inner catch doesn't match, so the outer one must.
	**/
	function testThrowingReturnInNestedSplitTry() {
		@:coroutine function f():Int {
			try {
				try {
					yield();
					return thrower();
				} catch (e:haxe.exceptions.NotImplementedException) {
					return -2;
				}
			} catch (e:Dynamic) {
				return -1;
			}
		}
		Assert.equals(-1, run(_ -> f()));
	}

	/**
		C2: hoisted locals are not saved before an implicit exception.

		`src/coro/coroToTexpr.ml:249`: `state.cs_el <- restoring @ state.cs_el @ saving @ tail`.
		Hoisted vars are written back to their continuation fields only at the end of a state. If a
		non-suspending call throws in the middle of a state, the catch state restores the stale field.
		The Thrown branch of `make_sync_call_and_check`, used for `noSuspend` callees, is affected too.

		Fix options: (a) for states with `cb_catch <> None`, write hoisted variables through to the
		field at each assignment; (c) save before each potentially throwing expression. (a) is the
		simplest. Existing hoisting tests are in `tests/src/TestHoisting.hx`.
	**/
	function testHoistedLocalSavedBeforeThrow() {
		@:coroutine function f():Int {
			var x = 0;
			try {
				x = 1;
				thrower();
				yield();
			} catch (e:Dynamic) {
				return x;
			}
			return -2;
		}
		Assert.equals(1, run(_ -> f()));
	}

	@:coroutine static function thirteen() {
		yield();
		return 13;
	}

	@:coroutine static function yes() {
		yield();
		return true;
	}

	@:coroutine static function negate() {
		return -thirteen();
	}

	@:coroutine static function not() {
		return !yes();
	}

	@:coroutine static function complement() {
		return ~thirteen();
	}

	/**
		C3: a unary operator on a tail-call result is dropped. Only release builds are affected,
		because `-debug` disables tail-call optimization, so this test only fails without `-debug`.

		`src/coro/coroFromTexpr.ml:322-324`:
		`| TUnop(op,flag,e1) -> let cb = loop cb ret (* TODO: is this right? *) e1 in ...`
		passes `RTailReturn` through to the call, which then becomes a tail call
		(`NextSuspend(_, None)`, see the `RTailReturn` arm of `TCall` around `:441`), so the `TUnop`
		wrapper is never applied.

		Fix: handle it like `TCast`/`TParenthesis` (`ret_map_expr`-style mapping), or pass `RValue`
		when `ret` is a tail kind so that the unop is applied in the resume state. Remove the TODO.
		Related: `tests/src/issues/` Issue93.
	**/
	function testUnopOnTailCall() {
		Assert.equals(-13, run(_ -> negate()));
		Assert.equals(false, run(_ -> not()));
		Assert.equals(~13, run(_ -> complement()));
	}

	/**
		C4: wrong catch region for the block after a loop if the first `break` is inside a split `try`.

		`src/coro/coroFromTexpr.ml:720` `split_while` creates the `cb_next` block lazily (`AtomicLazy`),
		and it is forced at `:467` (`NextBreak (AtomicLazy.force (snd hd))`). `make_block`
		(`coroFunctions.ml`) captures `ctx.current_catch` at force time. If the first `break` sits
		inside a split `try`, the post-loop block inherits that try's catch, so exceptions after the
		loop go to the in-loop handler. Here, that makes the coroutine loop until it returns "looped".

		Fix: capture `ctx.current_catch` when `split_while` begins and create the lazy block with it.
		Check `split_switch` (`~:690`) and `split_try` (`~:733`) for the same pattern.
	**/
	function testCatchRegionAfterLoop() {
		@:coroutine function f():String {
			var n = 0;
			while (true) {
				try {
					yield();
					break;
				} catch (e:Dynamic) {
					n++;
					if (n > 3) {
						return "looped";
					}
				}
			}
			throw "after";
		}
		var result = null;
		var error = null;
		try {
			result = run(_ -> f());
		} catch (e:haxe.Exception) {
			error = e.message;
		}
		Assert.isNull(result);
		Assert.equals("after", error);
	}

	/**
		C5: `catch (e:haxe.ValueException)` never matches in coroutines.

		`src/coro/coroToTexpr.ml:555-570`: every typed catch tests `Std.isOfType(error.unwrap(), T)`
		and binds the unwrapped value. `throw "x"` is wrapped as `ValueException`, so `unwrap()`
		returns `"x"` and the `ValueException` catch never matches. The non-coroutine filter does this
		differently: `src/filters/exception/exceptions.ml:262` (`if is_haxe_exception current_t`).

		Fix: mirror `exceptions.ml`. For catch types where `is_haxe_exception` holds, test and bind
		the wrapped `etmp_error`, and use the unwrapped value only for other types. Reuse the helper
		from `exceptions.ml`. Also check whether `haxe.Exception` is in `wildcard_catches`.
	**/
	function testCatchValueException() {
		@:coroutine function f():Dynamic {
			try {
				yield();
				throw "x";
			} catch (e:haxe.ValueException) {
				return e.value;
			}
		}
		Assert.equals("x", run(_ -> f()));
	}

	/**
		C5: same as above, with an explicitly constructed `ValueException`.
	**/
	function testCatchExplicitValueException() {
		@:coroutine function f():Dynamic {
			try {
				yield();
				throw new haxe.ValueException(1);
			} catch (e:haxe.ValueException) {
				return e.value;
			}
		}
		Assert.equals(1, run(_ -> f()));
	}

	static var count = 0;

	@:coroutine static function inc() {
		count++;
		yield();
		return 10;
	}

	/**
		C6: operands to the left of a suspending operand are evaluated after the suspension.

		`src/coro/coroFromTexpr.ml`: `TBinop` at `:344-356`, `ordered_loop` at `:573` (used for array
		declarations at `:282-308`, object declarations and `TNew`), call arguments at `:369`. Operands
		to the left of a suspending operand are kept as expressions and evaluated in the resume state.
		Only coroutine-call arguments go through an affection check and get temps.

		Fix: extend that affection check / temp introduction to binop operands and the `ordered_loop`
		users. Avoid temps for constants and locals that can't be affected.
	**/
	function testBinopEvaluationOrder() {
		count = 0;
		Assert.equals(10, run(_ -> count + inc()));
	}

	function testArrayDeclEvaluationOrder() {
		count = 0;
		Assert.same([0, 10], run(_ -> [count, inc()]));
	}

	function testObjectDeclEvaluationOrder() {
		count = 0;
		final o = run(_ -> {a: count, b: inc()});
		Assert.equals(0, o.a);
		Assert.equals(10, o.b);
	}

	/**
		C8: `Context.plus` erases elements of the left operand.

		`std/haxe/coro/context/Context.hx:69-75`: `plus` copies every slot of the right operand,
		including `null`s, so an element that only the left operand has is overwritten with `null`
		if the right operand has any element with a higher key id.

		Fix: `if (v != null) out[k] = v;`. Document that `+` cannot remove elements (use `without`).
		The compiler repo test belongs in `tests/unit/src/unit/TestCoroutines.hx` or a new
		`TestCoroContext.hx`.
	**/
	function testContextPlusKeepsLeftElements() {
		final low = new Key<TestElement>("low");
		final high = new Key<TestElement>("high");
		final a = Context.create(new TestElement(low, "a-low"), new TestElement(high, "a-high"));
		final b = Context.create(new TestElement(high, "b-high"));
		final c = a + b;
		Assert.equals("a-low", c.get(low)?.name);
		Assert.equals("b-high", c.get(high)?.name);
	}

	/**
		C11a: `ImmediateScheduler` assumes a `Dispatcher` in the context.

		`std/haxe/coro/schedulers/ImmediateScheduler.hx:35`: `cont.context.get(Dispatcher).dispatch(...)`
		has no null check. `BaseContinuation.resume` falls back to `onDispatch()` if there is no
		dispatcher; do the same here by resuming the continuation directly.
	**/
	function testImmediateSchedulerWithoutDispatcher() {
		var called = false;
		new ImmediateScheduler().schedule(0, new FunctionContinuation(Context.empty, (_, _) -> called = true));
		Assert.isTrue(called);
	}
}
