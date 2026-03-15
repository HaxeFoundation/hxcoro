package atest;

typedef TestInfo = {
	name:String,
	timeout:Int,
	execute:hxcoro.task.NodeLambda<Dynamic>,
	?contextElements:Array<haxe.coro.context.IElement<Any>>
}
