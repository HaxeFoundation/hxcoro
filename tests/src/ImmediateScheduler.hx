import haxe.Timer;
import haxe.Int64;
import haxe.Exception;
import haxe.coro.schedulers.IScheduler;

class ImmediateScheduler implements IScheduler {
	public function new() {}

	public function schedule(ms:Int64, f:() -> Void) {
		if (ms != 0) {
			throw new Exception('Only immediate scheduling is allowed in this scheduler');
		}
		f();
		return null;
	}

	public function now() {
		return Timer.milliseconds();
	}
}