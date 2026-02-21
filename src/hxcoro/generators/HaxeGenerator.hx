package hxcoro.generators;

import haxe.Unit;
import haxe.coro.Coroutine;
import hxcoro.generators.Generator;

@:coroutine.scope(restrictedSuspension)
abstract HaxeYield<T>(Generator<T, Unit>) to Generator<T, Unit> from Generator<T, Unit> {
	@:op(a()) @:coroutine function next(value:T):Void {
		this.yield(value);
	}
}

/**
	A synchronous generator that can be used as an `Iterator`.
**/
abstract HaxeGenerator<T>(Generator<T, Unit>) from Generator<T, Unit> {
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
		Creates a new generator that produces values by calling and resuming `f`.

		The coroutine `f` is executed in a restricted suspension scope, which means
		that it cannot call arbitrary coroutines that might suspend.
	**/
	extern static inline overload public function create<T>(f:Coroutine<HaxeYield<T> -> Null<Iterable<T>>>):HaxeGenerator<T> {
		return new Generator(f);
	}

	extern static inline overload  public function create<T>(f:Coroutine<HaxeYield<T> -> Void>):HaxeGenerator<T> {
		return new Generator(yield -> {
			f(yield);
			null;
		});
	}
}