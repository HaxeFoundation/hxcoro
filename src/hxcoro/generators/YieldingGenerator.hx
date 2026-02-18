package hxcoro.generators;

interface YieldingGenerator<T, R> {
	@:coroutine function yield(value:T):R;
}
