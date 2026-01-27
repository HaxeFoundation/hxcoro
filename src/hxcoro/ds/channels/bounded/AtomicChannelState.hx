package hxcoro.ds.channels.bounded;

import hxcoro.concurrent.BackOff;
import hxcoro.concurrent.AtomicState;

enum abstract ChannelState(Int) to Int {
	final Open;
	final Draining;
	final Locked;
	final Closed;
}

@:forward
abstract AtomicChannelState(AtomicState<ChannelState>) {
	public function new() {
		this = new AtomicState(Open);
	}

	public function lock() {
		#if hxcoro_mt_debug
		var timeoutTime = haxe.Timer.milliseconds() + 5000;
		#end
		var state = this.load();
		while (true) {
			switch state {
				case Open, Draining:
					var next = this.compareExchange(state, Locked);
					if (next == state) {
						return next;
					} else {
						state = next;

						BackOff.backOff();

						continue;
					}
				case Locked:
					BackOff.backOff();
					#if hxcoro_mt_debug
					if (haxe.Timer.milliseconds() >= timeoutTime) {
						trace("CHANNEL TIMEOUT");
						throw 'Channel timeout';
					}
					#end
					state = this.load();
				case Closed:
					return state;
			}
		}
	}
}