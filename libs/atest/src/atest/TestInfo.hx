package atest;

typedef TestInfo = {
	name:String,
	timeout:Int,
	execute:hxcoro.task.NodeLambda<Dynamic>
}
