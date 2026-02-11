package hxcoro.generators;

import haxe.Unit;
import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CoroutineException;
import hxcoro.Coro.*;

@:coroutine.restrictedSuspension
typedef Yield<T, R> = Coroutine<T -> R>;

private class GeneratorImpl<T, R> extends Dispatcher implements IContinuation<Unit> {
	public var context(get, null):Context;

	final f:Coroutine<Yield<T, R> -> Void>;
	var nextValue:Null<T>;
	var nextStep:Null<IContinuation<R>>;
	var raisedException:Null<Exception>;
	var resumed:Bool;

	public function new(f:Coroutine<Yield<T, R> -> Void>) {
		this.context = Context.create(this);
		this.f = f;
		resumed = false;
	}

	function get_context() {
		return context;
	}

	function get_scheduler() {
		return throw new CoroutineException('Cannot access scheduler on Generator contexts');
	}

	public function hasNext() {
		if (nextStep == null) {
			f(this, yield);
		}
		return !resumed;
	}

	public function next(value:R) {
		if (raisedException != null) {
			resumed = true;
			throw raisedException;
		}
		var current = nextValue;
		nextStep.resume(value, null);
		return current;
	}

	public function resume(result:Null<Unit>, error:Null<Exception>) {
		if (error != null) {
			raisedException = error;
		} else {
			resumed = true;
		}
	}

	public function dispatch(obj:IDispatchObject) {
		obj.onDispatch();
	}

	@:coroutine function yield(value:T):R {
		resumed = false;
		nextValue = value;
		return suspend(cont -> {
			nextStep = cont;
		});
	}
}

/**
	A synchronous generator that can be used as an `Iterator`.
**/
abstract SyncGenerator<T>(GeneratorImpl<T, Unit>) from GeneratorImpl<T, Unit> {
	/**
		@see `Iterator.hasNext`
	**/
	public inline function hasNext():Bool {
		return this.hasNext();
	}

	/**
		@see `Iterator.next`
	**/
	public inline function next():Null<T> {
		return this.next(Unit);
	}

	/**
		Creates a new generator that produces values by calling and resuming `f`.

		The coroutine `f` is executed in a restricted suspension scope, which means
		that it cannot call arbitrary coroutines that might suspend.
	**/
	static public function create<T>(f:Coroutine<Yield<T, Unit> -> Void>):SyncGenerator<T> {
		return new GeneratorImpl(f);
	}
}

abstract SyncValueGenerator<T, R>(GeneratorImpl<T, R>) from GeneratorImpl<T, R> {
	public inline function hasNext() {
		return this.hasNext();
	}

	public inline function next(value:R) {
		return this.next(value);
	}

	static public function create<T, R>(f:Coroutine<Yield<T, R> -> Void>):SyncValueGenerator<T, R> {
		return new GeneratorImpl(f);
	}
}