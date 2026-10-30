import haxe.coro.Coroutine;

/**
	The JavaScript-style yield API passed to `Es6Generator.create` functions.
**/
@:coroutine.scope(restrictedSuspension)
abstract Es6Yield<T, R>(Generator<T, R>) to Generator<T, R> from Generator<T, R> {
	/**
		Offers `value` as the next element and returns the value that the consumer passes
		to its subsequent `Es6Generator.next` call.
	**/
	@:coroutine public function next(value:T):R {
		return this.yield(value);
	}
}

/**
	A synchronous generator modeled after JavaScript generators, which can be used as
	an `Iterator`. In addition, the consumer can pass values of type `R` back into the
	generator by calling `next(value)`.
**/
abstract Es6Generator<T, R>(Generator<T, R>) from Generator<T, R> {
	/**
		@see `Iterator.hasNext`
	**/
	public inline function hasNext() {
		return this.hasNext();
	}

	/**
		@see `Iterator.next`
	**/
	extern public overload inline function next() {
		return this.next();
	}

	/**
		Returns the next element and resumes the generator, with `value` becoming the
		result of the `Es6Yield.next` call that offered the element.
	**/
	extern public overload inline function next(value:R) {
		return this.nextWith(value);
	}

	@:to inline function toIterable():Iterable<T> {
		return this;
	}

	/**
		Creates a new generator that produces values by calling and resuming `f`.

		The coroutine `f` is executed in a restricted suspension scope, which means
		that it cannot call arbitrary coroutines that might suspend.
	**/
	static public function create<T, R>(f:Coroutine<Es6Yield<T, R> -> Void>):Es6Generator<T, R> {
		return new Generator(yield -> {
			f(yield);
			return null;
		});
	}
}