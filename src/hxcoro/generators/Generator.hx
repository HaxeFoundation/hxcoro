package hxcoro.generators;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
import hxcoro.Coro.*;
import haxe.coro.dispatchers.SelfDispatcher;
import haxe.coro.schedulers.ImmediateScheduler;

/**
	The synchronous generator underlying `HaxeGenerator`, `CsGenerator` and
	`Es6Generator`. The generator function is executed on the calling thread, driven
	by calls to `hasNext` and `next`.
**/
class Generator<T, R> extends SuspensionResult<Iterator<T>> implements IContinuation<Iterable<T>> implements YieldingGenerator<T, R>{
	public var context(get, null):Context;

	final f:Coroutine<Generator<T, R> -> Iterable<T>>;
	var nextValue:Null<T>;
	var nextStep:Null<IContinuation<R>>;

	/**
		Creates a new `Generator` instance that runs `f` to obtain values.

		`f` starts executing on the first call to `hasNext`. If it returns a non-null
		iterable, its elements are offered as the final values of this generator.
	**/
	public function new(f:Coroutine<Generator<T, R> -> Iterable<T>>) {
		super(Pending);
		static final generatorContext = Context.create(new SelfDispatcher(new ImmediateScheduler()));
		this.context = generatorContext;
		this.f = f;
	}

	function get_context() {
		return context;
	}

	/**
		Returns `true` if more elements exist, `false` otherwise. If the generator
		function threw an exception, this returns `true` and the next call to `next`
		rethrows it.
	**/
	public function hasNext() {
		return switch (state) {
			case Pending if (nextStep == null):
				// Start the coro.
				f(this, this);
				hasNext(); // recurse
			case Pending:
				true;
			case Thrown:
				true;
			case Returned:
				result != null && result.hasNext();
		}
	}

	/**
		Returns the next element. This method must only be called after a prior call to
		`hasNext` returned `true`. It is equivalent to `nextWith(null)`.
	**/
	public function next() {
		return nextWith(null);
	}

	/**
		Like `next`, but additionally resumes the generator function with `value` as
		the result of the `yield` call that offered the returned element.
	**/
	@:nullSafety(Off)
	public function nextWith(value:Null<R>):T {
		return switch (state) {
			case Pending:
				var current = nextValue;
				nextStep.resume(value, null);
				return current;
			case Thrown:
				state = Returned;
				throw error;
			case Returned:
				if (result == null) {
					throw 'Invalid next call on already completed Generator';
				}
				result.next();
		}
	}

	public function resume(result:Null<Iterable<T>>, error:Null<Exception>) {
		if (error != null) {
			this.error = error;
			state = Thrown;
		} else if (result != null) {
			this.result = result.iterator();
			state = Returned;
		} else {
			state = Returned;
		}
	}

	/**
		Offers `value` as the next element and suspends until the consumer retrieves it.
		Returns the value passed to `nextWith`, or `null` if `next` was called.
	**/
	@:coroutine public function yield(value:T) {
		nextValue = value;
		return suspend(cont -> {
			nextStep = cont;
		});
	}

	/**
		Returns this generator, which allows using it as an `Iterable`.
	**/
	public function iterator() {
		return this;
	}
}