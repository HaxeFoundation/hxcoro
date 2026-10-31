package json;

/**
	A parsed JSON value.
**/
enum JsonValue {
	JNull;
	JBool(value:Bool);
	JNumber(value:Float);
	JString(value:String);
	JArray(values:Array<JsonValue>);
	/**
		An object. Its fields are kept in source order, including duplicate names.
	**/
	JObject(fields:Array<JsonField>);
}

typedef JsonField = {
	final name:String;
	final value:JsonValue;
}
