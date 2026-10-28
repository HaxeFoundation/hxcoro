package hxcoro.concurrent;

/**
	A mutual exclusion lock for coroutines, implemented as a `CoroSemaphore` with a
	single permit. `acquire` locks the mutex and `release` unlocks it.

	The mutex does not track ownership and is not reentrant. Calling `release` on an
	unlocked mutex throws a `SemaphoreFullException`.
**/
class CoroMutex extends CoroSemaphore {
	public function new() {
		super(1);
	}
}
