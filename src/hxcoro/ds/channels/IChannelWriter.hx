package hxcoro.ds.channels;

/**
	The writing end of a channel.
**/
interface IChannelWriter<T> {
	/**
		If the channel can accept `out` right away, writes it and returns `true`. Otherwise,
		for example if the channel is full or closed, returns `false` without suspending.
	**/
	function tryWrite(out:T):Bool;

	/**
		Writes `v`. If the channel is full, behaves according to the channel's `FullBehaviour`.
		Throws `hxcoro.ds.channels.exceptions.ChannelClosedException` if the channel is closed,
		except with `DropWrite`, which passes `v` to its callback instead.
	**/
	@:coroutine function write(v:T):Void;

	/**
		Suspends until there is space in the channel or the channel is closed. Returns
		`false` if the channel is closed.
	**/
	@:coroutine function waitForWrite():Bool;

	/**
		Closes the channel so that no more items can be written, and wakes up all
		suspended readers and writers. Items already in the channel can still be read.
		Calling `close` on a closed channel has no effect.
	**/
	function close():Void;
}