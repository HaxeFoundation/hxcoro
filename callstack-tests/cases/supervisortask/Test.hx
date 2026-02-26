package supervisortask;

class Test {
public static function run() {
try {
SupervisorTask.entry();
throw new haxe.Exception("Expected an exception from SupervisorTask");
} catch (e:haxe.Exception) {
checkStack(e);
}
}

static function checkStack(e:haxe.Exception) {
final stack = e.stack.asArray();
final r = new Inspector(stack).inspect([
File('supervisortask/SupervisorTask.hx'),
#if hl
// HL first-frame position is OS-dependent: definition line on
// Windows/macOS, throw line on Linux (same JIT behaviour as foobarbaz).
AnyLine,  // thrower() (line varies by HL OS)
#else
Line(13), // throw inside thrower()
#end
Line(19), // _ -> thrower() child-task entry lambda (at node.async() call)
Line(19), // coro frame for the node.async() call (same position)
// The supervisor() implementation contributes a frame from hxcoro/Coro.hx.
// We skip over it to avoid asserting on library-internal line numbers.
Skip('hxcoro/Coro.hx'), AnyLine,
File('supervisortask/SupervisorTask.hx'),
Line(17), // coro frame for the outer CoroRun.run lambda
]);
if (r != null)
throw r;
}
}
