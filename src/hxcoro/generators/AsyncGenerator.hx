package hxcoro.generators;

import haxe.Exception;
import haxe.Unit;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.context.Context;
import hxcoro.concurrent.AtomicState;
import hxcoro.concurrent.BackOff;

enum abstract AsyncGeneratorState(Int) to Int {
	final Created;
	final Running;
	final Modifying;
	final AwaitingValue;
	final ValueAvailable;
	final Stopped;
}

/**
	An asynchronous generator can be used like an iterator, but asynchronously. Its `hasNext`
	method blocks until either a value is available or until it is clear that no more values
	are going to arrive.

	This class is thread-safe with regards to a single producer (calling `yield`) and a single
	consumer (calling `hasNext`). It does not support multiple producers or consumers.
**/
class AsyncGenerator<T> extends SuspensionResult<Iterator<T>> implements IContinuation<Null<Iterable<T>>> implements YieldingGenerator<T, Unit> {
	public var context(get, null):Null<Context>;

	final f:Coroutine<AsyncGenerator<T> -> Null<Iterable<T>>>;
	var gState:AtomicState<AsyncGeneratorState>;
	var cont:Null<IContinuation<Any>>;
	var nextValue:Null<T>;

	/**
		Creates a new `AsyncGenerator` instance that runs `f` to obtain values.

		`f` starts executing on the first call to `hasNext`. If it finishes execution, this
		generator's `resume` method is called with the result. If that result is not null,
		its elements are offered as the final values of this generator.
	**/
	function new(f:Coroutine<AsyncGenerator<T> -> Null<Iterable<T>>>) {
		super(Pending);
		gState = new AtomicState(Created);
		this.f = f;
	}

	function get_context() {
		return context;
	}

	function start() {
		f(this, this);
	}

	function resolve() {
		if (error != null) {
			throw error;
		}
		if (result == null) {
			return false;
		} else if (result.hasNext()) {
			nextValue = result.next();
			return true;
		} else {
			return false;
		}
	}

	/**
		Returns `true` if more elements exist, `false` otherwise. This function may block
		until an element becomes available or this generator finishes.
	**/
	@:coroutine public function hasNext() {
		inline function awaitContinuation(cont:IContinuation<Any>) {
			this.cont = cont;
			gState.store(AwaitingValue);
		}
		while (true) {
			switch (gState.load()) {
				case Created:
					suspend(cont -> {
						context = cont.context;
						awaitContinuation(cont);
						start();
					});
				case Running:
					if (gState.compareExchange(Running, Modifying) == Running) {
						suspend(cont -> {
							awaitContinuation(cont);
						});
					}
				case Modifying:
					// wait
				case AwaitingValue:
					throw false; // invalid
				case ValueAvailable:
					return true;
				case Stopped:
					return resolve();
			}
			BackOff.backOff();
		}
	}

	/**
		Returns the next element. This method must only be called after a prior call to
		`hasNext` returned `true`.
	**/
	public function next() {
		final value = nextValue;
		if (gState.compareExchange(ValueAvailable, Running) == ValueAvailable) {
			@:nullSafety(Off) cont.callAsync();
		}
		return value;
	}

	/**
		Initializes the stopping procedure of this generator.

		If `error` is not null, it will be thrown by the next `hasNext` operation.

		Otherwise, if `result` is not null, its elements are offered as the final
		values of this generator.

		If there's a waiting `hasNext` continuation, it is resumed. A waiting `yield`
		continuation is not resumed.
	**/
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
		while (true) {
			switch (gState.load()) {
				case old = Created | Running | ValueAvailable:
					if (gState.compareExchange(old, Stopped) == old) {
						return;
					}
				case Modifying:
					// wait
				case AwaitingValue:
					if (gState.compareExchange(AwaitingValue, Stopped) == AwaitingValue) {
						// resume waiting hasNext
						@:nullSafety(Off) cont.callAsync();
						return;
					}
				case Stopped:
					return;
			}
			BackOff.backOff();
		}
	}

	/**
		Offers `value` as the next value.
	**/
	@:coroutine public function yield(value:T) {
		inline function offerValue(cont:IContinuation<Any>) {
			this.cont = cont;
			nextValue = value;
			gState.store(ValueAvailable);
		}
		while (true) {
			switch (gState.load()) {
				case Created | ValueAvailable:
					throw false; // invalid
				case Modifying:
					// wait
				case Running:
					if (gState.compareExchange(Running, Modifying) == Running) {
						suspend(cont -> {
							offerValue(cont);
						});
						return Unit;
					}
				case AwaitingValue:
					if (gState.compareExchange(AwaitingValue, Modifying) == AwaitingValue) {
						final awaitCont = cont;
						suspend(cont -> {
							offerValue(cont);
							@:nullSafety(Off) awaitCont.callAsync();
						});
						return Unit;
					}
				case Stopped:
					return Unit;
			}
			BackOff.backOff();
		}
	}

	extern static inline overload public function create<T>(f:Coroutine<AsyncYield<T> -> Null<Iterable<T>>>) {
		return new AsyncGenerator(f);
	}

	extern static inline overload public function create<T>(f:Coroutine<AsyncYield<T> -> Void>) {
		return new AsyncGenerator(gen -> {
			f(gen);
			null;
		});
	}
}

abstract AsyncYield<T>(AsyncGenerator<T>) to AsyncGenerator<T> from AsyncGenerator<T> {
	@:op(a()) @:coroutine function yield(value:T) {
		this.yield(value);
	}
}