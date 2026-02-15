package hxcoro.generators;

import haxe.Unit;
import haxe.coro.Coroutine;
import hxcoro.generators.Generator;

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

	static public function create<T, R>(f:Coroutine<Yield<T, Unit> -> Null<Iterable<T>>>):CsGenerator<T> {
		return new Generator(f);
	}
}