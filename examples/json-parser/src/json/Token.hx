package json;

/**
	A token and the byte offset at which it starts in the input.
**/
@:structInit
class Token {
	public final kind:TokenKind;
	public final position:Int;
}

enum TokenKind {
	TBraceOpen;
	TBraceClose;
	TBracketOpen;
	TBracketClose;
	TColon;
	TComma;
	TString(value:String);
	TNumber(value:Float);
	TTrue;
	TFalse;
	TNull;
	/**
		The end of the input. This is always the last token the lexer writes.
	**/
	TEof;
}
