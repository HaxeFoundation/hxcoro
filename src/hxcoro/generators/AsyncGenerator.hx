package hxcoro.generators;

import haxe.Exception;
import haxe.Unit;
import haxe.coro.CoroIntrinsics;
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

class AsyncGenerator<T> extends SuspensionResult<Iterator<T>> implements IContinuation<Iterable<T>> implements YieldingGenerator<T, Unit> {
	public var context(get, null):Context;

	final f:Coroutine<AsyncGenerator<T> -> Iterable<T>>;
	var gState:AtomicState<AsyncGeneratorState>;
	var cont:Null<IContinuation<Any>>;
	var nextValue:Null<T>;

	function new(f:Coroutine<AsyncGenerator<T> -> Iterable<T>>) {
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

	@:coroutine public function hasNext() {
		inline function awaitContinuation(cont:IContinuation<Any>) {
			this.cont = cont;
			gState.store(AwaitingValue);
		}
		while (true) {
			switch (gState.load()) {
				case Created:
					context = CoroIntrinsics.getContext();
					suspend(cont -> {
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

	public function next() {
		final value = nextValue;
		if (gState.compareExchange(ValueAvailable, Running) == ValueAvailable) {
			cont.callAsync();
		}
		return value;
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
						cont.callAsync();
						return;
					}
				case Stopped:
					return;
			}
			BackOff.backOff();
		}
	}

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
							awaitCont.callAsync();
						});
						return Unit;
					}
				case Stopped:
					return Unit;
			}
			BackOff.backOff();
		}
	}

	extern static inline overload public function create<T>(f:Coroutine<AsyncGeneratorApi<T> -> Null<Iterable<T>>>) {
		return new AsyncGenerator(f);
	}

	extern static inline overload public function create<T>(f:Coroutine<AsyncGeneratorApi<T> -> Void>) {
		return new AsyncGenerator(gen -> {
			f(gen);
			null;
		});
	}
}

abstract AsyncGeneratorApi<T>(AsyncGenerator<T>) to AsyncGenerator<T> from AsyncGenerator<T> {
	@:op(a()) @:coroutine function yield(value:T) {
		this.yield(value);
	}
}