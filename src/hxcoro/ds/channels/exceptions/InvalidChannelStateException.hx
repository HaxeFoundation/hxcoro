package hxcoro.ds.channels.exceptions;

import haxe.Exception;

class InvalidChannelStateException extends Exception {
	public function new() {
		super('Invalid channel state');
	}
}