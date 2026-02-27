import haxe.CallStack;
using StringTools;

enum InspectDirective {
	/** Switch the expected file for subsequent `Line` checks. **/
	File(file:String);
	/** Assert the next stack frame is in the current file at the given line. **/
	Line(line:Int);
	/** Assert the next stack frame is in the current file (any line). **/
	AnyLine;
	/**
		Consume the next stack frame if it is in the current file at the given line,
		otherwise do nothing. Useful when a frame may be absent on some platforms.
	**/
	OptionalLine(line:Int);
	/** Advance past frames until one matching `file` is found. **/
	Skip(file:String);
}

class InspectorFailure extends haxe.Exception {
	public function new(reason:String) {
		super(reason);
	}
}

/**
	Lightweight utility for asserting the shape of an exception call stack.
	Unlike a full diff, it lets tests pin only the frames they care about and
	skip over implementation-internal frames via `Skip`.
**/
class Inspector {
	final stack:Array<StackItem>;
	var offset:Int;
	var expectedFile:Null<String>;
	var inspectOffset:Int;

	public function new(stack:Array<StackItem>) {
		this.stack = stack;
		offset = 0;
		inspectOffset = -1;
	}

	/**
		Check `directives` against the stack. Returns `null` on success,
		or an `InspectorFailure` (with the full stack dump embedded) on the
		first mismatch.
	**/
	public function inspect(directives:Array<InspectDirective>):Null<InspectorFailure> {
		try {
			for (d in directives)
				doInspect(d);
			return null;
		} catch (e:InspectorFailure) {
			return e;
		}
	}

	function fail(index:Int, directive:InspectDirective, reason:String) {
		final lines = ['Failure at stack[${index}] / directive[${inspectOffset}] ($directive): $reason'];
		for (i => item in stack)
			lines.push('\t[$i] $item');
		throw new InspectorFailure(lines.join("\n"));
	}

	function doInspect(directive:InspectDirective) {
		++inspectOffset;
		switch (directive) {
			case File(file):
				expectedFile = file;

			case Line(expectedLine):
				final index = offset++;
				switch (stack[index]) {
					case null:
						fail(index, directive, 'stack went out of bounds at index $index');
					case FilePos(_, file, line):
						if (!file.endsWith(expectedFile))
							fail(index, directive, 'file "$file" should end with "$expectedFile"');
						if (line != expectedLine)
							fail(index, directive, 'line $line should be $expectedLine');
					case v:
						fail(index, directive, '$v should be FilePos');
				}

			case AnyLine:
				final index = offset++;
				switch (stack[index]) {
					case null:
						fail(index, directive, 'stack went out of bounds at index $index');
					case FilePos(_, file, _):
						if (!file.endsWith(expectedFile))
							fail(index, directive, 'file "$file" should end with "$expectedFile"');
					case v:
						fail(index, directive, '$v should be FilePos');
				}

			case OptionalLine(expectedLine):
				// Consume the frame only if it matches the current expected file and the
				// given line; silently skip otherwise. `expectedFile` is the file context
				// set by the most recent File(...) directive, the same as for Line/AnyLine.
				switch (stack[offset]) {
					case FilePos(_, file, line) if (file.endsWith(expectedFile) && line == expectedLine):
						offset++;
					case _:
				}

			case Skip(file):
				while (true) {
					if (offset == stack.length)
						fail(offset, directive, 'ran out of stack frames while skipping to "$file"');
					switch (stack[offset]) {
						case FilePos(Method(_) | LocalFunction(_), file2, _) if (file2.endsWith(file)):
							expectedFile = file;
							break;
						case _:
							offset++;
					}
				}
		}
	}
}
