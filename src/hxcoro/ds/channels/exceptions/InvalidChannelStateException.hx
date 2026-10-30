package hxcoro.ds.channels.exceptions;

import haxe.Exception;

/**
	Thrown when a channel operation finds the channel in an unexpected internal state.
**/
class InvalidChannelStateException extends Exception {
	public function new() {
		super('Invalid channel state');
	}
}