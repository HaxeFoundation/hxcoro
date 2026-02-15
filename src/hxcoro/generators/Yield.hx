package hxcoro.generators;

/**
	The basic yield API for generators, supporting only `yield(value)`.
**/
@:coroutine.restrictedSuspension
@:transitive
abstract Yield<T, R>(Generator<T, R>) to Generator<T, R> from Generator<T, R> {
	@:op(a()) @:coroutine function next(value:T):Void {
		this.yield(value);
	}
}
