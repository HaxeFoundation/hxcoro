package hxcoro.dispatchers;

/**
	An object that holds resources which must be released by calling `shutDown`.
**/
interface IShutDown {
	/**
		Shuts down this object and releases its resources.
	**/
	function shutDown():Void;
}