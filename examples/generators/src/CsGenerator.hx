import haxe.Unit;
import haxe.coro.Coroutine;
import hxcoro.Coro.*;

/**
	The C#-style yield API passed to `CsGenerator.create` functions.
**/
@:coroutine.scope(restrictedSuspension)
abstract CsYield<T, R>(Generator<T, R>) to Generator<T, R> from Generator<T, R> {
	/**
		Offers `value` as the next element, like C#'s `yield return`.
	**/
	@:coroutine public function yieldReturn(value:T):R {
		return this.yield(value);
	}

	/**
		Stops the generator, like C#'s `yield break`. Execution of the generator function
		does not continue after this call.
	**/
	@:coroutine public function yieldBreak() {
		this.resume(null, null);
		return suspend(_ -> {});
	}
}

/**
	A synchronous generator that can be used as an `Iterator`, with a C#-style
	yield API (see `CsYield`).
**/
abstract CsGenerator<T>(Generator<T, Unit>) from Generator<T, Unit> {
	/**
		@see `Iterator.hasNext`
	**/
	public inline function hasNext() {
		return this.hasNext();
	}

	/**
		@see `Iterator.next`
	**/
	public inline function next() {
		return this.next();
	}

	@:to inline function toIterable():Iterable<T> {
		return this;
	}

	/**
		Creates a new generator that produces values by calling and resuming `f`. If `f`
		returns a non-null iterable, its elements are offered after the yielded values.

		The coroutine `f` is executed in a restricted suspension scope, which means
		that it cannot call arbitrary coroutines that might suspend.
	**/
	static public function create<T, R>(f:Coroutine<CsYield<T, Unit> -> Null<Iterable<T>>>):CsGenerator<T> {
		return new Generator(f);
	}
}