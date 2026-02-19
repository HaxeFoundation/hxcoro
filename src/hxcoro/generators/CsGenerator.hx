package hxcoro.generators;

import haxe.Unit;
import haxe.coro.Coroutine;
import hxcoro.generators.Generator;

@:coroutine.restrictedSuspension
abstract CsYield<T, R>(Generator<T, R>) to Generator<T, R> from Generator<T, R> {
	@:coroutine public function yieldReturn(value:T):R {
		return this.yield(value);
	}

	@:coroutine public function yieldBreak() {
		this.resume(null, null);
		return suspend(_ -> {});
	}
}

abstract CsGenerator<T>(Generator<T, Unit>) from Generator<T, Unit> {
	public inline function hasNext() {
		return this.hasNext();
	}

	public inline function next() {
		return this.next();
	}

	@:to inline function toIterable():Iterable<T> {
		return this;
	}

	static public function create<T, R>(f:Coroutine<CsYield<T, Unit> -> Null<Iterable<T>>>):CsGenerator<T> {
		return new Generator(f);
	}
}