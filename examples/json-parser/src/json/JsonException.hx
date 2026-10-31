package json;

/**
	Thrown by the lexer and the parser on invalid input.
**/
class JsonException extends haxe.Exception {
	/**
		The byte offset in the input at which the error occurred.
	**/
	public final position:Int;

	public function new(message:String, position:Int) {
		super('$message at position $position');
		this.position = position;
	}
}
