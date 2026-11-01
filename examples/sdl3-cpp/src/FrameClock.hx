import haxe.Timer;
import haxe.coro.IContinuation;
import hxcoro.Coro.*;

/**
	Lets coroutines wait for the next frame, like `yield return null` in Unity or `awaitFrame`
	in kotlinx-coroutines-android.

	The main loop calls `tick` once per frame. It must only be used from the main thread.
**/
class FrameClock {
	var waiting:Array<IContinuation<Float>> = [];

	public function new() {}

	/**
		Suspends until the next frame begins and returns its time in seconds.
	**/
	@:coroutine public function awaitFrame():Float {
		return suspendCancellable(cont -> {
			waiting.push(cont);
			_ -> {
				waiting.remove(cont);
			}
		});
	}

	/**
		Resumes all coroutines waiting for the next frame.
	**/
	public function tick() {
		if (waiting.length == 0) {
			return;
		}
		final time = Timer.stamp();
		// Coroutines that wait again are resumed in the next frame, not in this one.
		final resumed = waiting;
		waiting = [];
		for (cont in resumed) {
			cont.resume(time, null);
		}
	}
}
