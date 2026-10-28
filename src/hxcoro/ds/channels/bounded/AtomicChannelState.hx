package hxcoro.ds.channels.bounded;

import hxcoro.concurrent.BackOff;
import hxcoro.concurrent.AtomicState;

/**
	The state of a bounded channel.
**/
enum abstract ChannelState(Int) to Int {
	/**
		The channel can be written to and read from.
	**/
	final Open;
	/**
		Closed for writing, but there are still items to read.
	**/
	final Draining;
	/**
		An operation currently has exclusive access to the channel.
	**/
	final Locked;
	/**
		Closed for writing, and all items have been read.
	**/
	final Closed;
}

/**
	The atomically updated state of a bounded channel, which doubles as its lock.
**/
@:forward
abstract AtomicChannelState(AtomicState<ChannelState>) {
	public function new() {
		this = new AtomicState(Open);
	}

	/**
		Spins until the state can be set to `Locked` and returns the previous state, or returns `Closed` without locking.
	**/
	public function lock() {
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

					state = this.load();
				case Closed:
					return state;
			}
		}
	}
}