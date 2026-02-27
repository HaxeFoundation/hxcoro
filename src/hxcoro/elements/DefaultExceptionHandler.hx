package hxcoro.elements;

import haxe.CallStack;
import haxe.Exception;
import haxe.PosInfos;
import haxe.coro.CoroStackItem;
import haxe.coro.IStackFrame;
import haxe.coro.Tls;
import haxe.coro.context.Context;
import haxe.coro.context.ExceptionHandler;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;

using StringTools;

private class StartedException {
	public final exception:Exception;
	public final coroStack:Array<CoroStackItem>;

	public function new(exception:Exception, coroStack:Array<CoroStackItem>) {
		this.exception = exception;
		this.coroStack = coroStack;
	}

	#if sys
	public function dump() {
		Sys.println("Exception stack:");
		for (item in exception.stack.asArray()) {
			Sys.print("\t");
			Sys.println(item);
		}
		Sys.println("Coro stack:");
		for (item in coroStack) {
			Sys.print("\t");
			Sys.println(item);
		}
	}
	#end
}

private class SynchronousRun implements IElement<SynchronousRun> implements ISynchronousRun {
	public static final key = new Key<SynchronousRun>('SynchronousRun');

	public var context(get, null):Context;

	final entryPos:PosInfos;

	// Static so only one pthread TLS key is ever created (macOS has PTHREAD_KEYS_MAX=512;
	// creating a new key per CoroRun.run() call exhausts the limit and causes failures).
	static final thrownException = new Tls<StartedException>();

	// Native call stack captured at construction time, used to detect nested coro scenarios
	// and extract bridge frames between coro worlds.
	final capturedStack:Null<Array<StackItem>>;

	public function new(context:Context, entryPos:PosInfos) {
		this.context = context.with(this);
		this.entryPos = entryPos;
		capturedStack = CallStack.callStack();
	}

	function get_context() {
		return context;
	}

	public function startException(frame:IStackFrame, exception:Exception) {
		var frameItem = frame.getStackItem();
		if (frameItem == null) {
			// If we have no frame item on our continuation, just bail.
			return exception;
		}

		// Collect coro frames from the continuation chain.
		var chainFrames = [];
		var currentFrame = frame;
		while (currentFrame != null) {
			final item = currentFrame.getStackItem();
			if (item != null) {
				chainFrames.push(item);
			}
			currentFrame = currentFrame.callerFrame();
		}

		thrownException.value = new StartedException(exception, chainFrames);
		return exception;
	}

	public function buildCallStack(frame:IStackFrame):Void {
		final exception = thrownException.value;
		if (exception == null || exception.coroStack.length == 0) {
			return;
		}
		thrownException.value = null;

		final newStack = [];
		final coroStack = exception.coroStack;
		final exceptionStack = exception.exception.stack.asArray();

		function patchFirstCoroStack(file:String, line:Int, column:Int) {
			switch (coroStack[0]) {
				case ClassFunction(cls, func, _, _, _):
					coroStack[0] = ClassFunction(cls, func, file, line, column);
				case LocalFunction(id, _, _, _):
					coroStack[0] = LocalFunction(id, file, line, column);
				case PosInfo(_):
			}
		}

		for (item in exceptionStack) {
			switch (item) {
				case FilePos(StackItem.Method(_, "invokeResume"), file, line, column):
					// Only patch the coro stack position when we have actual Haxe source info.
					// On PHP, Python etc. the invokeResume file is a compiled target path, not
					// a .hx source file, so patching would overwrite the correct coro stack info.
					if (file != null && file.endsWith(".hx")) {
						patchFirstCoroStack(file, line, column);
					}
					break;
				case FilePos(_, file, _, _) if (file != null && file.endsWith(".hx")):
					// Collect Haxe source frames that appear before invokeResume (e.g. the
					// actual throwing location and its sync callers on JVM/eval targets).
					newStack.push(item);
				case _:
					// Not a Haxe source frame — either a compiled target path (PHP, Python, C++)
					// or Neko's null-file format. Stop collecting to avoid polluting the
					// reconstructed stack with platform-internal frames.
					break;
			}
		}

		// Emit coro frames. For the last PosInfo frame (the entry point of this run),
		// check whether we are nested inside another coro world by looking for an outer
		// coro's invokeResume in our capturedStack. If found, inject the sync bridge frames
		// (the call chain between the two coro worlds) and the outer invokeResume entry
		// directly into newStack, so the outer run's buildCallStack can process them via
		// the normal invokeResume mechanism. This avoids any cross-thread data passing.
		final lastIndex = coroStack.length - 1;
		for (i => frame in coroStack) {
			switch (frame) {
				case ClassFunction(cls, func, file, line, column):
					newStack.push(StackItem.FilePos(StackItem.Method(cls, func), file, line, column));
				case LocalFunction(id, file, line, column):
					newStack.push(StackItem.FilePos(StackItem.LocalFunction(id), file, line, column));
				case PosInfo(p):
					if (i == lastIndex) {
						final bridge = extractBridgeFromCapturedStack(p);
						if (bridge != null) {
							// Nested scenario: inject bridge frames and the outer invokeResume.
							// The outer run's buildCallStack will find the invokeResume entry and
							// use it to patch the outer coro's position, same as the normal path.
							for (f in bridge.frames) {
								newStack.push(f);
							}
							newStack.push(bridge.outerInvokeResume);
							// Don't emit PosInfo — the bridge frames capture the same info.
						} else {
							newStack.push(StackItem.FilePos(StackItem.Method(p.className, "coro"), p.fileName, p.lineNumber));
						}
					} else {
						newStack.push(StackItem.FilePos(StackItem.Method(p.className, "coro"), p.fileName, p.lineNumber));
					}
			}
		}

		exception.exception.stack = newStack;
	}

	// Walk capturedStack to find sync frames between the entry point (identified by posInfo's
	// file and line) and the outer coro's invokeResume. Returns the bridge frames and the
	// invokeResume StackItem if found, or null if this is not a nested scenario.
	function extractBridgeFromCapturedStack(posInfo:PosInfos):Null<{frames:Array<StackItem>, outerInvokeResume:StackItem}> {
		if (capturedStack == null) return null;

		var entryFound = false;
		final bridgeFrames = [];
		var outerInvokeResume:Null<StackItem> = null;

		for (frame in capturedStack) {
			if (!entryFound) {
				// Locate the call site matching the PosInfos of the CoroRun entry.
				switch (frame) {
					case FilePos(_, file, line) if (file.endsWith(posInfo.fileName) && line == posInfo.lineNumber):
						entryFound = true;
					case _:
				}
			} else {
				// Collect sync frames until the outer coro's invokeResume boundary.
				switch (frame) {
					case FilePos(StackItem.Method(_, "invokeResume"), _, _, _):
						outerInvokeResume = frame;
						break;
					case _:
						bridgeFrames.push(frame);
				}
			}
		}

		if (outerInvokeResume == null) return null;
		return {frames: bridgeFrames, outerInvokeResume: outerInvokeResume};
	}

	public function complete() {
		// Clear state to avoid keeping unnecessary references around.
		thrownException.value = null;
	}

	public function getKey() {
		return key;
	}
}

/**
	The default `ExceptionHandler` implementation, which reconstructs the coroutine call stack
	from the continuation chain and inserts it into the exception's stack trace.
**/

class DefaultExceptionHandler extends ExceptionHandler {
	public function new() {

	}

	public function startSynchronousRun(context:Context, p:PosInfos) {
		return new SynchronousRun(context, p);
	}

	public function startException(context:Context, frame:IStackFrame, exception:Exception):Exception {
		return context.get(SynchronousRun).startException(frame, exception);
	}

	public function buildCallStack(context:Context, frame:IStackFrame):Void {
		context.get(SynchronousRun).buildCallStack(frame);
	}
}
