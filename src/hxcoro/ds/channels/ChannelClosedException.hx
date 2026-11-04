package hxcoro.ds.channels;

import haxe.Exception;

/**
	Thrown when reading from a channel that is closed and empty, or writing to a closed channel.
**/
class ChannelClosedException extends Exception {
	public function new() {
		super('Channel closed');
	}
}