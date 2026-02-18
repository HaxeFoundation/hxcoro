package hxcoro.generators;

/**
	The basic yield API for generators, supporting only `yield(value)`.
**/
@:coroutine.restrictedSuspension
@:transitive
abstract Yield<T, R>(YieldingGenerator<T, R>) to YieldingGenerator<T, R> from YieldingGenerator<T, R> {
	@:op(a()) @:coroutine function next(value:T):Void {
		this.yield(value);
	}
}
