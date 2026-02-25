import haxe.CallStack;
import haxe.Exception;
import callstack.CallStackInspector;

#if debug
class TestCallStack extends utest.Test {
	function test() {
		try {
			callstack.Bottom.entry();
			Assert.fail("Exception expected");
		} catch(e:haxe.exceptions.NotImplementedException) {
			final stack = e.stack.asArray();
			var inspector = new CallStackInspector(stack);
			var r = inspector.inspect([
				#if (eval || cpp)
				// On eval and cpp the native exception stack carries the actual sync
				// throw site (Top.hx frames) and invokeResume patches the first coro
				// frame to its call position.
				File('callstack/Top.hx'),
					Line(4),
					Line(8),
					Line(12),
				File('callstack/CoroUpper.hx'),
					Line(8),
					Line(6),
					Line(6),
					Line(6),
					Line(6),
					Line(15),
				Skip('callstack/SyncMiddle.hx'),
					Line(4),
					Line(8),
				File('callstack/CoroLower.hx'),
					Line(6),
				Skip('callstack/Bottom.hx'),
					Line(4)
				#else
				// On other targets the native stack does not expose .hx source frames
				// before invokeResume, so we only get the reconstructed coro chain.
				// The first frame is unpatched (definition line), and sync bridge
				// frames (Top.hx, SyncMiddle.syncFun1) are absent.
				File('callstack/CoroUpper.hx'),
					Line(3),
					Line(6),
					Line(6),
					Line(6),
					Line(6),
					Line(15),
				Skip('callstack/SyncMiddle.hx'),
					Line(4),
				Skip('callstack/CoroLower.hx'),
					Line(3),
				Skip('callstack/Bottom.hx'),
					Line(4)
				#end
			]);
			checkFailure(stack, r);
		}
	}

	function checkFailure(stack:Array<StackItem>, r:Null<CallStackInspectorFailure>) {
		if (r == null) {
			Assert.pass();
		} else {
			var i = 0;
			var lines = stack.map(item -> '\t[${i++}] $item');
			Assert.fail('${r.toString()}\n${lines.join("\n")}');
		}
	}

	function testFooBazBaz() {
		function checkStack(e:Exception) {
			final stack = e.stack.asArray();
			var inspector = new CallStackInspector(stack);
			var r = inspector.inspect([
				File('callstack/FooBarBaz.hx'),
				#if cpp
				// cpp gives the coroutine definition line for the top frame instead
				// of the actual throw position (inaccurate positions on cpp).
				Line(6),
				Line(12),
				Line(16),
				#else
				Line(7),
				Line(12),
				// TODO: sync stack (foo calling bar) not reconstructed yet
				// Line(16)
				#end
			]);
			checkFailure(stack, r);
		}
		try {
			CoroRun.run(callstack.FooBarBaz.foo);
			Assert.fail("Exception expected");
		} catch(e:Exception) {
			checkStack(e);
		}

		try {
			CoroRun.run(scope -> {
				scope.async(scope -> {
					scope.async(_ -> {
						callstack.FooBarBaz.foo();
					});
				});
			});
			Assert.fail("Exception expected");
		} catch (e:Exception) {
			checkStack(e);
		}
	}
}
#end