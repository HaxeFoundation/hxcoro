package hxcoro.generators;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
import hxcoro.Coro.*;
import hxcoro.dispatchers.SelfDispatcher;
import hxcoro.schedulers.ImmediateScheduler;

@:coroutine.restrictedSuspension
abstract Yield<T, R>(Generator<T, R>) {
	public var generator(get, never):Generator<T, R>;

	public inline function new(generator:Generator<T, R>) {
		this = generator;
	}

	inline function get_generator() {
		return this;
	}

	@:op(a()) @:coroutine function next(value:T):Void {
		this.yield(value);
	}
}

class Generator<T, R> extends SuspensionResult<Iterator<T>> implements IContinuation<Iterable<T>> {
	public var context(get, null):Context;

	final f:Coroutine<Yield<T, R> -> Iterable<T>>;
	var nextValue:Null<T>;
	var nextStep:Null<IContinuation<R>>;

	public function new(f:Coroutine<Yield<T, R> -> Iterable<T>>) {
		super(Pending);
		static final generatorContext = Context.create(new SelfDispatcher(new ImmediateScheduler()));
		this.context = generatorContext;
		this.f = f;
	}

	function get_context() {
		return context;
	}

	public function hasNext() {
		return switch (state) {
			case Pending if (nextStep == null):
				// Start the coro.
				final result = f(this, new Yield(this));
				switch (result.state) {
					case Pending:
					case Returned | Thrown:
						resume(result.result, result.error);
				}
				hasNext(); // recurse
			case Pending:
				true;
			case Thrown:
				true;
			case Returned:
				result != null && result.hasNext();
		}
	}

	public function next() {
		return nextWith(null);
	}

	public function nextWith(value:Null<R>) {
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

	@:coroutine public function yield(value:T) {
		nextValue = value;
		return suspend(cont -> {
			nextStep = cont;
		});
	}

	public function iterator() {
		return this;
	}
}