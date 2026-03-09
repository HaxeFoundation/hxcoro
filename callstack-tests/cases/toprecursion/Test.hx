package toprecursion;

class Test {
	public static function run() {
		try {
			Bottom.entry();
			throw new haxe.Exception("Expected an exception from TopRecursion");
		} catch (e:haxe.exceptions.NotImplementedException) {
			final stack = e.stack.asArray();
			final r = new Inspector(stack).inspect([
				#if (eval || cpp || jvm || hl)
				// On eval, cpp, jvm and hl the native exception stack carries the sync throw
				// site (Top.hx frames) and the invokeResume mechanism patches the
				// first coro frame to its actual call position.
				File('toprecursion/Top.hx'),
					Line(4),  // throw in throwing()
					Line(8),  // topCall2 calling throwing
					Line(12), // topCall1 calling topCall2
				File('toprecursion/CoroUpper.hx'),
					Line(8),  // recursion base case calling topCall1 (patched by invokeResume)
					Line(6),  // recursion -> recursion recursive call (x4)
					Line(6),
					Line(6),
					Line(6),
					Line(15), // bar calling recursion
				Skip('toprecursion/SyncMiddle.hx'),
					Line(4),  // lambda in syncFun2 (CoroRun.run call site)
					Line(8),  // syncFun1 calling syncFun2 (sync bridge frame)
				File('toprecursion/CoroLower.hx'),
					Line(6),  // foo calling syncFun1 (patched by outer invokeResume)
				Skip('toprecursion/Bottom.hx'),
					Line(4)   // lambda in entry (CoroRun.run call site)
				#else
				// On other targets the native stack does not expose .hx source frames
				// before invokeResume, so we only see the reconstructed coro chain.
				// The first frame keeps its compile-time position (definition line),
				// and sync bridge frames (Top.hx, syncFun1) are absent.
				File('toprecursion/CoroUpper.hx'),
					Line(3),  // recursion entry (unpatched definition position)
					Line(6),  // recursion -> recursion (x4)
					Line(6),
					Line(6),
					Line(6),
					Line(15), // bar calling recursion
				Skip('toprecursion/SyncMiddle.hx'),
					Line(4),  // lambda in syncFun2
				Skip('toprecursion/CoroLower.hx'),
					Line(3),  // foo entry (unpatched)
				Skip('toprecursion/Bottom.hx'),
					Line(4)   // lambda in entry
				#end
			]);
			if (r != null)
				throw r;
		}
	}
}
