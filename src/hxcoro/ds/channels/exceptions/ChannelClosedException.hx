package hxcoro.ds.channels.exceptions;

import haxe.Exception;

class ChannelClosedException extends Exception {
	public function new() {
		super('Channel closed');
	}
}