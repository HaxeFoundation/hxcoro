package hxcoro.ds.channels.bounded;

import hxcoro.concurrent.AtomicState;

enum abstract ChannelState(Int) to Int {
	final Open;
	final Locked;
	final Closed;
}

@:forward
abstract AtomicChannelState(AtomicState<ChannelState>) {
	public function new() {
		this = new AtomicState(Open);
	}

	public function lock() {
		while (true) {
			switch this.compareExchange(Open, Locked) {
				case Open:
					return true;
				case Locked:
					// loop
				case Closed:
					return false;
			}
		}
	}
}