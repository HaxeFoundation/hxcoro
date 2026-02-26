import hxcoro.run.Setup;
import hxcoro.run.LoopRun;
import hxcoro.task.NodeLambda;

var setupFactory:() -> hxcoro.run.Setup.LoopSetup = Setup.createDefault;

function run<T>(lambda:NodeLambda<T>#if debug, ?callPos:haxe.PosInfos#end):T {
	final s = setupFactory();
	final context = s.createContext();
	final task = LoopRun.runTask(s.loop, context, lambda#if debug, callPos#end);
	s.close();
	return switch (task.getError()) {
		case null: task.get();
		case error: throw error;
	};
}
