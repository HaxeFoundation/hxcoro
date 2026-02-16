package hxcoro.concurrent;

import hxcoro.concurrent.CoroLatch;

/**
	A barrier allows waiting for a specified number of arrivals, then lets them through
	and closes itself again, at which point the process can be repeated.
**/
@:forward("arrive", "arriveAndDrop", "wait")
abstract CoroBarrier(CoroLatchImpl) {

	static function noOpCallback() {}

	/**
		Creates a new `CoroBarrier` instance with the specified `counter` value. If
		`onCompletion` is provided, it will be called every time the counter reaches 0,
		before any waiting continuations are resumed.
	**/
	public function new(counter:Int, ?onCompletion:() -> Void) {
		this = new CoroLatchImpl(counter, onCompletion ?? noOpCallback);
	}

	/**
		Decreases the internal counter value by 1 and waits for it to reach 0.

		This is equivalent to calling `arrive(1)` followed by `wait()`.

		See `arrive` for details about the arrival process.
	**/
	@:coroutine public function arriveAndWait() {
		this.arriveAndWait(1);
	}
}