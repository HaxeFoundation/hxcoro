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
abstract Yield<T, R>(Generator<T, R>) {
	public var generator(get, never):Generator<T, R>;

	public inline function new(generator:Generator<T, R>) {
		this = generator;
	}

	inline function get_generator() {
		return this;
	}

	@:op(a()) @:coroutine function next(value:T):Void {
		this.yieldReturn(value);
	}
}

private enum ResumeResult<T> {
	Unresumed;
	Error(error:haxe.Exception);
	Result(it:Iterator<T>);
	Done;
}

class Generator<T, R> extends Dispatcher implements IContinuation<Iterable<T>> {
	public var context(get, null):Context;

	final f:Coroutine<Yield<T, R> -> Iterable<T>>;
	var nextValue:Null<T>;
	var nextStep:Null<IContinuation<R>>;
	var raisedException:Null<Exception>;
	var resumeResult:ResumeResult<T>;

	public function new(f:Coroutine<Yield<T, R> -> Iterable<T>>) {
		this.context = Context.create(this);
		this.f = f;
		resumeResult = Unresumed;
	}

	function get_context() {
		return context;
	}

	function get_scheduler() {
		return throw new CoroutineException('Cannot access scheduler on Generator contexts');
	}

	public function hasNext() {
		return switch (resumeResult) {
			case Unresumed if (nextStep == null):
				final result = f(this, new Yield(this));
				switch (result.state) {
					case Pending:
						hasNext(); // recurse
					case Returned | Thrown:
						resume(result.result, result.error);
						hasNext(); // recurse
				}
			case Unresumed:
				true;
			case Error(_):
				true;
			case Done:
				false;
			case Result(it):
				it.hasNext();
		}
	}

	public function next() {
		return nextWith(null);
	}

	public function nextWith(value:Null<R>) {
		return switch (resumeResult) {
			case Unresumed:
				var current = nextValue;
				nextStep.resume(value, null);
				return current;
			case Error(exc):
				resumeResult = Done;
				throw raisedException;
			case Result(it):
				it.next();
			case Done:
				throw 'Invalid next call on already completed Generator';
		}
	}

	public function resume(result:Null<Iterable<T>>, error:Null<Exception>) {
		if (error != null) {
			resumeResult = Error(error);
		} else if (result != null) {
			resumeResult = Result(result.iterator());
		} else {
			resumeResult = Done;
		}
	}

	public function dispatch(obj:IDispatchObject) {
		obj.onDispatch();
	}

	@:coroutine public function yieldReturn(value:T) {
		nextValue = value;
		return suspend(cont -> {
			nextStep = cont;
		});
	}

	@:coroutine public function yieldBreak() {
		resumeResult = Done;
		return suspend(_ -> {});
	}

	public function iterator() {
		return this;
	}
}