package hxcoro.concurrent;

import hxcoro.concurrent.CoroLatch;

@:forward("arrive", "arriveAndDrop", "wait")
abstract CoroBarrier(CoroLatchImpl) {

	static function noOpCallback() {}

	public function new(counter:Int, ?onCompletion:() -> Void) {
		this = new CoroLatchImpl(counter, onCompletion ?? noOpCallback);
	}

	/**
		Decreases the internal counter value by `n` and waits for it to reach 0.

		This is equivalent to calling `arrive(n)` followed by `wait()`.
	**/
	@:coroutine public function arriveAndWait() {
		this.arriveAndWait(1);
	}
}