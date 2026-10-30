/**
	The common interface of generators that values can be yielded to.
**/
interface YieldingGenerator<T, R> {
	/**
		Offers `value` as the next element of the generator. The meaning of the returned
		value depends on the implementation.
	**/
	@:coroutine function yield(value:T):R;
}
