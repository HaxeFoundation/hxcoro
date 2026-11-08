package hxcoro.ds.channels.bounded;

import hxcoro.concurrent.LockableAtomic;

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
		Closed for writing, and all items have been read.
	**/
	final Closed;
}

/**
	The atomically updated state of a bounded channel, which doubles as its lock.
**/
@:forward(load, tryLock, unlock)
abstract AtomicChannelState(LockableAtomic<ChannelState>) {
	public inline function new() {
		this = new LockableAtomic(Open);
	}

	/**
		Spins until the lock is taken and returns the previous state, or returns `Closed` without locking.
	**/
	public inline function lock():ChannelState {
		return this.lockUnless(Closed);
	}
}
