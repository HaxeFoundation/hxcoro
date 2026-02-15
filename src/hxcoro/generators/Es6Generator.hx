package hxcoro.generators;

import haxe.coro.Coroutine;
import hxcoro.generators.Generator;

@:coroutine.restrictedSuspension
abstract Es6Yield<T, R>(Yield<T, R>) to Yield<T, R> from Yield<T, R> {
	public inline function new(yield:Yield<T, R>) {
		this = yield;
	}

	@:coroutine public function next(value:T):R {
		return this.generator.yield(value);
	}
}

abstract Es6Generator<T, R>(Generator<T, R>) from Generator<T, R> {
	public inline function hasNext() {
		return this.hasNext();
	}

	extern public overload inline function next() {
		return this.next();
	}

	extern public overload inline function next(value:R) {
		return this.nextWith(value);
	}

	@:to inline function toIterable():Iterable<T> {
		return this;
	}

	static public function create<T, R>(f:Coroutine<Es6Yield<T, R> -> Void>):Es6Generator<T, R> {
		return new Generator(yield -> {
			f(yield);
			return null;
		});
	}
}