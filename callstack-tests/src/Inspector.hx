import haxe.CallStack;
using StringTools;

enum InspectDirective {
	/** Switch the expected file for subsequent `Line` checks. **/
	File(file:String);
	/** Assert the next stack frame is in the current file at the given line. **/
	Line(line:Int);
	/** Assert the next stack frame is in the current file (any line). **/
	AnyLine;
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

	function fail(directive:InspectDirective, reason:String) {
		final lines = ['Failure at stack[${offset}] / directive[${inspectOffset}] ($directive): $reason'];
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
						fail(directive, 'stack went out of bounds at index $index');
					case FilePos(_, file, line):
						if (!file.endsWith(expectedFile))
							fail(directive, 'file "$file" should end with "$expectedFile"');
						if (line != expectedLine)
							fail(directive, 'line $line should be $expectedLine');
					case v:
						fail(directive, '$v should be FilePos');
				}

			case AnyLine:
				final index = offset++;
				switch (stack[index]) {
					case null:
						fail(directive, 'stack went out of bounds at index $index');
					case FilePos(_, file, _):
						if (!file.endsWith(expectedFile))
							fail(directive, 'file "$file" should end with "$expectedFile"');
					case v:
						fail(directive, '$v should be FilePos');
				}

			case Skip(file):
				while (true) {
					if (offset == stack.length)
						fail(directive, 'ran out of stack frames while skipping to "$file"');
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
