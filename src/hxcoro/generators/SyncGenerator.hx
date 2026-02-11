package hxcoro.generators;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CoroutineException;
import hxcoro.Coro.*;

@:coroutine.restrictedSuspension
typedef Yield<T> = Coroutine<T -> Void>;

private class GeneratorImpl<T> extends Dispatcher implements IContinuation<Any> {
	public var context(get, null):Context;

	final f:Coroutine<Yield<T> -> Void>;
	var nextValue:Null<T>;
	var nextStep:Null<IContinuation<T>>;
	var resumed:Bool;

	public function new(f:Coroutine<Yield<T> -> Void>) {
		this.context = Context.create(this);
		this.f = f;
		resumed = true;
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
		} else if (!resumed) {
			nextStep.resume(null, null);
		}
		return !resumed;
	}

	public function next() {
		return nextValue;
	}

	public function resume(result:Null<Any>, error:Null<Exception>) {
		resumed = true;
		if (error != null) {
			throw error;
		}
	}

	public function dispatch(obj:IDispatchObject) {
		obj.onDispatch();
	}

	@:coroutine function yield(value:T) {
		resumed = false;
		nextValue = value;
		suspend(cont -> {
			nextStep = cont;
		});
	}
}

/**
	A synchronous generator that can be used as an `Iterator`.
**/
abstract SyncGenerator<T>(GeneratorImpl<T>) {
	/**
		@see `Iterator.hasNext`
	**/
	public inline function hasNext() {
		return this.hasNext();
	}

	/**
		@see `Iterator.next`
	**/
	public inline function next() {
		return this.next();
	}

	/**
		Creates a new generator that produces values by calling and resuming `f`.

		The coroutine `f` is executed in a restricted suspension scope, which means
		that it cannot call arbitrary coroutines that might suspend.
	**/
	static public function create<T>(f:Coroutine<Yield<T> -> Void>) {
		return new GeneratorImpl(f);
	}
}